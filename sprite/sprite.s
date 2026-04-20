; =============================================================================
; NES Sprite Demo — Day 6
; A face sprite glides across the screen, driven by the NMI/VBlank interrupt.
;
; Memory map (CPU RAM):
;   $0000         sprite_x   — zero-page variable tracking sprite 1's X position
;   $0200–$02FF   shadow OAM — sprite data staged here, DMA'd to PPU each frame
;
; PPU registers used:
;   $2000 PPUCTRL   — NMI enable (bit 7)
;   $2001 PPUMASK   — rendering enable (bits 1-4)
;   $2002 PPUSTATUS — VBlank flag / address latch reset
;   $2003 OAMADDR   — OAM write start position
;   $2005 PPUSCROLL — scroll position (set to 0,0)
;   $2006 PPUADDR   — PPU address pointer (two writes: high then low byte)
;   $2007 PPUDATA   — PPU data port (auto-increments after each write)
;   $4014 OAMDMA    — triggers DMA copy from CPU RAM page → PPU OAM
; =============================================================================

.segment "HEADER"
    .byte $4E, $45, $53, $1A    ; "NES" magic identifier + DOS EOF marker
    .byte $02                   ; 2 PRG-ROM banks (2 × 16KB = 32KB)
    .byte $01                   ; 1 CHR-ROM bank (8KB — tile graphics)
    .byte $00                   ; mapper 0 (NROM), horizontal mirroring
    .byte $00                   ; mapper 0 high nibble, standard iNES format
    .byte $00, $00, $00, $00    ; padding bytes 8–11
    .byte $00, $00, $00, $00    ; padding bytes 12–15

; =============================================================================
; CHR-ROM — tile graphics data (8KB total, 512 tiles of 8×8 pixels)
; Each tile = 16 bytes: 8 bytes plane 0 + 8 bytes plane 1
; Each pixel's color index = (plane1 bit << 1) | plane0 bit  →  0, 1, 2, or 3
; =============================================================================
.segment "CHARS_BG"

  ; Tile $00 (PPU $0000) — blank / sky (nametable defaults to 0, so this = empty background)
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 0
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 1

  ; Tile $01  (PPU $0010)
  .byte $20, $AA, $76, $DD, $B7, $6D, $DB, $76  ; plane 0
  .byte $00, $00, $89, $22, $48, $92, $24, $89  ; plane 1

  ; Tile $02 (PPU $0020) — grass fill
  .byte $D5, $AB, $76, $DD, $B7, $6D, $DB, $76  ; plane 0
  .byte $2A, $54, $89, $22, $48, $92, $24, $89  ; plane 1

.segment "CHARS_SPR"
  .incbin "sam-robot.chr"


; =============================================================================
; CODE segment — PRG-ROM, mapped to CPU $8000–$FFFF
; =============================================================================
.segment "CODE"

; --- PPU register aliases (makes code readable instead of using raw addresses) ---
PPUCTRL   = $2000   ; control flags: NMI enable, sprite size, pattern table select
PPUMASK   = $2001   ; rendering flags: show bg, show sprites, show left-edge columns
PPUSTATUS = $2002   ; read-only: VBlank flag (bit 7), sprite 0 hit (bit 6)
PPUADDR   = $2006   ; PPU address bus: write high byte then low byte
PPUDATA   = $2007   ; PPU data port: read/write PPU memory at current PPUADDR

; --- Zero-page variables (fast RAM — single-byte address = shorter, faster instructions) ---
sam_x = $00         ; Sam's X position (left edge of left column, 0–255)
sam_y = $01         ; Sam's Y position (top row, 0–255)
frame_timer = $02
anim_frame = $03
moving = $04
sound_timer = $05

; =============================================================================
; Data tables — live in PRG-ROM (read-only, CPU can index into them)
; =============================================================================

; =============================================================================
; Sam — 2×4 meta-sprite (8 OAM entries, tiles $00–$07 from SPR pattern table)
;
; Tile layout:
;   [$00][$01]   row 0  (top)
;   [$02][$03]   row 1
;   [$04][$05]   row 2
;   [$06][$07]   row 3  (bottom, feet at grass line)
;
; OAM format per entry: [Y, tile, attributes, X]
;   Y = scanline the sprite appears on (sprite draws on Y+1, so subtract 1 from desired row)
;   X = left edge of sprite in pixels
;   Attributes = %vhpppppp  (v=flip-V, h=flip-H, pp=palette 0–3)
;
; Sam is centered at X=120 (two tiles: $78 and $80), top at pixel row 184.
; =============================================================================
sam_oam:
    .byte $B7, $00, $00, $78   ; row 0 left  — tile $00, Y=184, X=120
    .byte $B7, $01, $00, $80   ; row 0 right — tile $01, Y=184, X=128
    .byte $BF, $10, $00, $78   ; row 1 left  — tile $02, Y=192, X=120
    .byte $BF, $11, $00, $80   ; row 1 right — tile $03, Y=192, X=128
    .byte $C7, $20, $00, $78   ; row 2 left  — tile $04, Y=200, X=120
    .byte $C7, $21, $00, $80   ; row 2 right — tile $05, Y=200, X=128

anim_tiles:
    .byte $00, $01, $02, $03
    .byte $10, $11, $12, $13
    .byte $20, $21, $22, $23

; Palettes: 8 total × 4 bytes = 32 bytes, written to PPU $3F00–$3F1F
;   $3F00–$3F0F = background palettes 0–3
;   $3F10–$3F1F = sprite palettes 0–3  (PPU mirrors $3F10/$3F14/$3F18/$3F1C back to $3F00,
;                                        but the color slots $3F11–$3F13 etc. are independent)
; Byte 0 of each palette = color index 0 = transparent/universal BG color
palette_data:
    ; --- Background palettes ---
    .byte $21, $1A, $08, $26    ; BG  palette 0: sky / green / brown / gold
    .byte $23, $1A, $28, $17    ; BG  palette 1: dark / green / yellow / orange
    .byte $23, $14, $2C, $30    ; BG  palette 2: dark / purple / pink / white
    .byte $23, $11, $1C, $27    ; BG  palette 3: dark / teal / lime / gold
    ; --- Sprite palettes ---
    .byte $FF, $11, $27, $10    ; SPR palette 0: skin tone / red / gold / white
    .byte $21, $16, $37, $28    ; SPR palette 1: dark / red / skin / gold
    .byte $21, $06, $17, $28    ; SPR palette 2: dark / red / orange / yellow
    .byte $0D, $16, $37, $07    ; slot0=$0D slot1=$05 slot2=$37 slot3=$07

; Attribute table: 64 bytes covering the full 32×30 nametable ($23C0–$23FF)
; 8 rows of 8 bytes = 64 entries, each controlling a 4×4 tile block (2 bits per quadrant)
; All $00 = entire screen uses palette 0
attr_data:
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows  0– 3
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows  4– 7
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows  8–11
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows 12–15
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows 16–19
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows 20–23
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows 24–27
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; rows 28–31

; =============================================================================
; reset_handler — entry point after power-on or reset
; Runs once to initialize everything, then spins forever in @loop.
; All per-frame work happens in nmi_handler instead.
; =============================================================================
.proc reset_handler
    sei             ; disable IRQ interrupts (we only use NMI)
    cld             ; disable decimal mode (not used on NES hardware)
    ldx #$FF
    txs             ; set stack pointer to $01FF (top of stack page)

    ; --- Wait for PPU to warm up (takes ~2 VBlanks after power-on) ---
@vblankwait1:
    bit PPUSTATUS       ; read $2002 — clears address latch, tests VBlank flag (bit 7)
    bpl @vblankwait1    ; BPL = "branch if plus" = loop while bit 7 is 0 (not VBlank)

@vblankwait2:
    bit PPUSTATUS       ; wait for second VBlank — PPU is fully ready after this
    bpl @vblankwait2

    ; --- Load background palettes into PPU $3F00 ---
    bit PPUSTATUS       ; reset address latch (must always do before writing PPUADDR)
    lda #$3F
    sta PPUADDR         ; set PPU address high byte → $3F__
    lda #$00
    sta PPUADDR         ; set PPU address low byte  → $3F00

    ldx #$00
@palette_loop:
    lda palette_data,X  ; load palette byte at index X
    sta PPUDATA         ; write to PPU (address auto-increments after each write)
    inx
    cpx #$20            ; 32 bytes = 8 palettes × 4 bytes (4 BG + 4 sprite)
    bne @palette_loop

    ; --- Load attribute table into PPU $23C0 ---
    ; The attribute table controls which palette each 4×4 tile block uses.
    lda PPUSTATUS       ; reset address latch
    lda #$23
    sta PPUADDR         ; high byte → $23__
    lda #$C0
    sta PPUADDR         ; low byte  → $23C0

    ldx #$00
@attr_loop:
    lda attr_data,X
    sta PPUDATA
    inx
    cpx #$40            ; 64 bytes = full attribute table ($23C0–$23FF)
    bne @attr_loop

    ; --- Write background tiles to nametable ---
    ; NES nametable = 32×30 grid at PPU $2000. Each byte = tile index to display.
    ; Rows 0–26 are left at 0 (tile $00 = blank sky — default nametable value).
    ; Row 27 = tile $01 (grass top edge)   PPU $2360
    ; Row 28 = tile $02 (grass fill)       PPU $2380
    ; Row 29 = tile $02 (grass fill)       PPU $23A0

    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$60            ; → PPU $2360 (row 27, col 0)
    sta PPUADDR
    lda #$01            ; tile $01 = grass top edge
    ldx #$00
@row27:
    sta PPUDATA
    inx
    cpx #$20            ; 32 columns
    bne @row27

    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$80            ; → PPU $2380 (row 28, col 0)
    sta PPUADDR
    lda #$02            ; tile $02 = grass fill
    ldx #$00
@row28:
    sta PPUDATA
    inx
    cpx #$20
    bne @row28

    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$A0            ; → PPU $23A0 (row 29, col 0)
    sta PPUADDR
    lda #$02            ; tile $02 = grass fill
    ldx #$00
@row29:
    sta PPUDATA
    inx
    cpx #$20
    bne @row29

    ; --- Initialize Sam's starting position ---
    lda #$78            ; X = 120 (centered)
    sta sam_x
    lda #$B7            ; Y = 183 (top of Sam, feet land just above grass)
    sta sam_y

    ; --- Clear entire shadow OAM page to $FF (hides all 64 sprite slots) ---
    ; DMA copies all 256 bytes of $0200–$02FF to PPU OAM every frame.
    ; Any slot with Y < 240 is visible, so uninitialized slots = garbage sprites.
    ; Setting Y = $FF puts every slot off-screen before we fill in the ones we need.
    lda #$FF
    ldx #$00
@clear_oam:
    sta $0200,X         ; fill entire page with $FF
    inx
    bne @clear_oam      ; inx wraps $FF→$00, so this loops exactly 256 times

    ; --- Copy Sam's OAM table into shadow RAM ($0200–$021F) ---
    ; sam_oam is 8 sprites × 4 bytes = 32 bytes
    ldx #$00
@sam_oam_loop:
    lda sam_oam,X
    sta $0200,X
    inx
    cpx #$18            ; 24 bytes = 16 sprites
    bne @sam_oam_loop

    ; --- Trigger initial OAM DMA ---
    ; Copy shadow OAM ($0200–$02FF) → PPU's internal OAM memory
    lda #$00
    sta $2003           ; OAMADDR = 0 (start DMA at beginning of PPU OAM)
    lda #$02
    sta $4014           ; DMA page $02 → copies $0200–$02FF to PPU OAM

    ; --- Set scroll position (must come after all PPUADDR writes) ---
    lda #$00
    sta $2005           ; PPUSCROLL X = 0
    sta $2005           ; PPUSCROLL Y = 0

    ; --- Enable rendering ---
    lda #$1E            ; %00011110 = show sprites + background, show left-edge columns
    sta PPUMASK

    ; --- Enable NMI ---
    ; Without this, VBlank fires silently and nmi_handler never runs.
    lda #$88            ; %10001000 = bit 7 NMI enable, bit 3 sprites use $1000, bit 4 BG uses $0000
    sta PPUCTRL

    ; --- Enable APU Pulse 1 ---
    lda #$01
    sta $4015           ; bit 0 = pulse 1 on

    lda #$08            ; %00001000 — sweep disabled, negate=1, shift=0
    sta $4001           ; negate bit prevents overflow silencing at low frequencies

    ; --- Spin forever — all real work happens in nmi_handler ---
@loop:
    jmp @loop

.endproc

; =============================================================================
; nmi_handler — called automatically by hardware at the start of every VBlank
; (~60 times per second). This is where all per-frame updates happen.
;
; VBlank is the only safe window to update PPU memory (palette, nametable, OAM).
; We update our shadow OAM in CPU RAM, then DMA the whole buffer to PPU OAM.
; =============================================================================
.proc nmi_handler
    ; --- Read controller 1 ---
    ; Writing 1 then 0 to $4016 "strobes" the controller — it latches all button states.
    ; After that, each read of $4016 returns the next button in bit 0 (1=pressed, 0=not).
    ; Button order is fixed by hardware: A, B, Select, Start, Up, Down, Left, Right.
    lda #$01
    sta $4016           ; strobe on  — latch button states
    lda #$00
    sta $4016           ; strobe off — ready to clock out buttons one at a time

    sta moving          ; clear moving flag — $00 already in A from strobe off

    lda $4016           ; A      — read and discard
    lda $4016           ; B      — read and discard
    lda $4016           ; Select — read and discard
    lda $4016           ; Start  — read and discard

    lda $4016           ; Up
    and #$01            ; isolate bit 0 (the button state)
    beq @no_up          ; 0 = not pressed, skip
    dec sam_y           ; move Sam up (Y decreases toward top of screen)
    lda #$01
    sta moving
@no_up:

    lda $4016           ; Down
    and #$01
    beq @no_down
    inc sam_y           ; move Sam down
    lda #$01
    sta moving
@no_down:

    lda $4016           ; Left
    and #$01
    beq @no_left
    dec sam_x           ; move Sam left
    lda #$01
    sta moving
@no_left:

    lda $4016           ; Right
    and #$01
    beq @no_right
    inc sam_x           ; move Sam right
    lda #$01
    sta moving
@no_right:

    ; --- Update shadow OAM with Sam's new position ---
    ; Sam is 2 tiles wide × 4 tiles tall. Each tile is 8×8 pixels.
    ; Left column X = sam_x, right column X = sam_x + 8.
    ; Row Y positions step down by 8 each row.
    ;
    ; OAM entry format: [Y, tile, attributes, X]
    ; We only update bytes 0 (Y) and 3 (X) — tile and attributes never change.

    ; Y positions (byte 0 of each entry, 4 bytes apart)
    lda sam_y
    sta $0200           ; sprite 0 Y  (row 0, left)
    sta $0204           ; sprite 1 Y  (row 0, right)
    clc
    adc #$08
    sta $0208           ; sprite 2 Y  (row 1, left)
    sta $020C           ; sprite 3 Y  (row 1, right)
    clc
    adc #$08
    sta $0210           ; sprite 4 Y  (row 2, left)
    sta $0214           ; sprite 5 Y  (row 2, right)

    ; X positions (byte 3 of each entry)
    lda sam_x
    sta $0203           ; sprite 0 X  (left column, row 0)
    sta $020B           ; sprite 2 X  (left column, row 1)
    sta $0213           ; sprite 4 X  (left column, row 2)
    clc
    adc #$08
    sta $0207           ; sprite 1 X  (right column, row 0)
    sta $020F           ; sprite 3 X  (right column, row 1)
    sta $0217           ; sprite 5 X  (right column, row 2)

    ; --- Movement chirp ---
    lda moving
    beq @no_moving_sound
    inc sound_timer
    lda sound_timer
    cmp #$10
    bne @no_moving_sound
        lda #$00
        sta sound_timer
        lda #$BF        ; %10_11_1111
                        ;   1111       volume:           1111 = 15 (max)
                        ;   1          length halt:      1 = hold note (ignore length counter)
                        ;   1          constant volume:  1 = fixed level (not envelope)
                        ;  10          duty cycle:       10 = 50% square wave
        sta $4000
        lda #$F1        ; A1 Note
        sta $4002
        lda #$0F        ; retrigger length counter, restart note
        sta $4003
        jmp @after_moving_sound
@no_moving_sound:
    lda #$00
    sta $4000           ; silence when not moving
@after_moving_sound:

    ; --- Animation timer ---
    lda moving
    bne @do_anim
    lda #$00
    sta anim_frame
    jmp @skip_anim
@do_anim:
    inc frame_timer
    lda frame_timer
    cmp #$10
    bne @skip_anim
        lda #$00
        sta frame_timer
        lda anim_frame
        eor #$01
        sta anim_frame
@skip_anim:
    ; --- Update all 6 tile bytes in shadow OAM ---
    ; Each row in anim_tiles is 4 bytes (2 per pose × 2 poses)
    ; anim_frame=0 → offset 0, anim_frame=1 → offset 2

    lda anim_frame
    asl                 ; 0→0, 1→2
    tax

    lda anim_tiles,x    ; head left
    sta $0201
    inx
    lda anim_tiles,x    ; head right
    sta $0205

    lda anim_frame
    asl
    clc
    adc #$04            ; skip to body row in table
    tax

    lda anim_tiles,x    ; body left
    sta $0209
    inx
    lda anim_tiles,x    ; body right
    sta $020D

    lda anim_frame
    asl
    clc
    adc #$08            ; skip to feet row in table
    tax

    lda anim_tiles,x    ; feet left
    sta $0211
    inx
    lda anim_tiles,x    ; feet right
    sta $0215

    ; --- DMA shadow OAM → PPU OAM ---
    ; Push the updated shadow OAM to the PPU every frame without exception.
    lda #$00
    sta $2003           ; OAMADDR = 0
    lda #$02
    sta $4014           ; DMA page $02 → PPU OAM

    rti

.endproc

; =============================================================================
; irq_handler — we don't use IRQs (SEI disables them at startup)
; =============================================================================
.proc irq_handler
    rti
.endproc

; =============================================================================
; Interrupt vectors — hardware reads these addresses on startup and interrupts
;   $FFFA–$FFFB  NMI vector   → address of nmi_handler
;   $FFFC–$FFFD  Reset vector → address of reset_handler
;   $FFFE–$FFFF  IRQ vector   → address of irq_handler
; =============================================================================
.segment "VECTORS"
    .word nmi_handler    ; $FFFA
    .word reset_handler  ; $FFFC
    .word irq_handler    ; $FFFE

