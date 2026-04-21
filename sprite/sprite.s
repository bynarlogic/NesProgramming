; =============================================================================
; NES Sprite Demo — Day 7 (Sound Design)
; Sam the robot walks around and plays a musical note per direction:
;   Up    → G4 (~392 Hz)
;   Down  → A4 (~440 Hz)
;   Left  → E4 (~330 Hz)
;   Right → C4 (~262 Hz)
;
; Memory map (CPU RAM):
;   $0000  sam_x        — Sam's X position
;   $0001  sam_y        — Sam's Y position
;   $0002  frame_timer  — animation frame timer
;   $0003  anim_frame   — current animation frame (0 or 1)
;   $0004  moving       — nonzero if any direction held this frame
;   $0200–$02FF shadow OAM — sprite data staged here, DMA'd to PPU each frame
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
;
; APU registers used:
;   $4000  Pulse 1 duty + envelope (volume, constant/envelope, length halt)
;   $4001  Pulse 1 sweep (disabled)
;   $4002  Pulse 1 period low byte
;   $4003  Pulse 1 period high bits + length counter retrigger
;   $4015  APU channel enable flags
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
; =============================================================================
.segment "CHARS_BG"

  ; Tile $00 — blank sky
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 0
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 1

  ; Tile $01 — grass top edge
  .byte $20, $AA, $76, $DD, $B7, $6D, $DB, $76  ; plane 0
  .byte $00, $00, $89, $22, $48, $92, $24, $89  ; plane 1

  ; Tile $02 — grass fill
  .byte $D5, $AB, $76, $DD, $B7, $6D, $DB, $76  ; plane 0
  .byte $2A, $54, $89, $22, $48, $92, $24, $89  ; plane 1

.segment "CHARS_SPR"
  .incbin "sam-robot.chr"


; =============================================================================
; CODE segment — PRG-ROM, mapped to CPU $8000–$FFFF
; =============================================================================
.segment "CODE"

; --- PPU register aliases ---
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUADDR   = $2006
PPUDATA   = $2007

; --- Zero-page variables ---
sam_x       = $00
sam_y       = $01
frame_timer = $02
anim_frame  = $03
moving      = $04
sound_timer = $05
duty_cycle  = $06
note_index  = $07   ; which note to play this frame (set during button reads)

; =============================================================================
; Data tables
; =============================================================================

sam_oam:
    .byte $B7, $00, $00, $78   ; row 0 left
    .byte $B7, $01, $00, $80   ; row 0 right
    .byte $BF, $10, $00, $78   ; row 1 left
    .byte $BF, $11, $00, $80   ; row 1 right
    .byte $C7, $20, $00, $78   ; row 2 left
    .byte $C7, $21, $00, $80   ; row 2 right

anim_tiles:
    .byte $00, $01, $02, $03
    .byte $10, $11, $12, $13
    .byte $20, $21, $22, $23

; =============================================================================
; Note period tables — C major scale, octave 2 (C2–C3)
;
; Period formula (NTSC): period = 1,789,773 / (16 × frequency) - 1
; The 11-bit period splits across two registers:
;   $4002 = low 8 bits
;   $4003 bits 2-0 = high 3 bits  (bits 7-3 = length counter load)
;
; Periods are ~4× larger than octave 4 — frequency halves each octave down,
; so period doubles. Octave 2 = two doublings from octave 4.
;
; Index:    0     1     2     3     4     5     6     7
; Note:     C2    D2    E2    F2    G2    A2    B2    C3
; Freq(Hz): 65    73    82    87    98   110   123   131
; Period:  1709  1523  1357  1280  1140  1016   905   854
; =============================================================================
note_lo:
    .byte $AD   ; C2  period = $06AD
    .byte $F3   ; D2  period = $05F3
    .byte $4D   ; E2  period = $054D
    .byte $00   ; F2  period = $0500
    .byte $74   ; G2  period = $0474
    .byte $F8   ; A2  period = $03F8
    .byte $89   ; B2  period = $0389
    .byte $56   ; C3  period = $0356

note_hi:
    .byte $06   ; C2
    .byte $05   ; D2
    .byte $05   ; E2
    .byte $05   ; F2
    .byte $04   ; G2
    .byte $03   ; A2
    .byte $03   ; B2
    .byte $03   ; C3

palette_data:
    ; --- Background palettes ---
    .byte $21, $1A, $08, $26
    .byte $23, $1A, $28, $17
    .byte $23, $14, $2C, $30
    .byte $23, $11, $1C, $27
    ; --- Sprite palettes ---
    .byte $FF, $11, $27, $10
    .byte $21, $16, $37, $28
    .byte $21, $06, $17, $28
    .byte $0D, $16, $37, $07

attr_data:
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; =============================================================================
; play_note macro — writes to APU pulse 1 registers to sound a note
;
; Usage: play_note <index>   where index is 0–7 into note_lo/note_hi
;
; $4000: %10_1_1_1111
;         ││ │ │ └───── volume = 15 (max)
;         ││ │ └─────── constant volume (not envelope decay)
;         ││ └───────── length counter halt (hold note until silenced)
;         └┘─────────── duty cycle 50% (full square wave)
;
; $4002: low 8 bits of period
; $4003: note_hi OR $08
;   bits 2-0 = high 3 bits of period
;   bit  3   = part of length counter load — must be nonzero to avoid instant silence
;   writing $4003 always retrriggers (restarts) the note
; =============================================================================
.macro play_note index
    lda duty_cycle
    sta $4000
    ldx #index
    lda note_lo,x
    sta $4002
    lda note_hi,x
    ora #$08            ; ensure length counter is nonzero; retrigger note
    sta $4003
.endmacro


; =============================================================================
; reset_handler — entry point after power-on or reset
; =============================================================================
.proc reset_handler
    sei
    cld
    ldx #$FF
    txs

    ; --- Wait for PPU to warm up ---
@vblankwait1:
    bit PPUSTATUS
    bpl @vblankwait1
@vblankwait2:
    bit PPUSTATUS
    bpl @vblankwait2

    ; --- Load all 8 palettes (32 bytes) into PPU $3F00 ---
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR

    ldx #$00
@palette_loop:
    lda palette_data,X
    sta PPUDATA
    inx
    cpx #$20
    bne @palette_loop

    ; --- Load attribute table into PPU $23C0 ---
    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$C0
    sta PPUADDR

    ldx #$00
@attr_loop:
    lda attr_data,X
    sta PPUDATA
    inx
    cpx #$40
    bne @attr_loop

    ; --- Write background tiles ---
    ; Row 27 ($2360) — grass top
    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$60
    sta PPUADDR
    lda #$01
    ldx #$00
@row27:
    sta PPUDATA
    inx
    cpx #$20
    bne @row27

    ; Row 28 ($2380) — grass fill
    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$80
    sta PPUADDR
    lda #$02
    ldx #$00
@row28:
    sta PPUDATA
    inx
    cpx #$20
    bne @row28

    ; Row 29 ($23A0) — grass fill
    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$A0
    sta PPUADDR
    lda #$02
    ldx #$00
@row29:
    sta PPUDATA
    inx
    cpx #$20
    bne @row29

    ; --- Initialize Sam's starting position ---
    lda #$78
    sta sam_x
    lda #$B7
    sta sam_y

    ; --- Clear entire shadow OAM to $FF (hides all 64 sprite slots) ---
    lda #$FF
    ldx #$00
@clear_oam:
    sta $0200,X
    inx
    bne @clear_oam

    ; --- Copy Sam's 6-sprite OAM entries into shadow RAM ---
    ldx #$00
@sam_oam_loop:
    lda sam_oam,X
    sta $0200,X
    inx
    cpx #$18            ; 6 sprites × 4 bytes = 24 bytes
    bne @sam_oam_loop

    ; --- Initial OAM DMA ---
    lda #$00
    sta $2003
    lda #$02
    sta $4014

    ; --- Set scroll ---
    lda #$00
    sta $2005
    sta $2005

    ; --- Enable rendering ---
    lda #$1E
    sta PPUMASK

    ; --- Enable NMI ---
    lda #$88            ; bit 7 = NMI enable, bit 3 = sprites from $1000
    sta PPUCTRL

    ; --- Enable APU Pulse 1 ---
    lda #$01
    sta $4015           ; bit 0 = pulse 1 on

    lda #$08            ; sweep off; negate=1 prevents overflow silence at low freqs
    sta $4001

@loop:
    jmp @loop

.endproc


; =============================================================================
; nmi_handler — called every VBlank (~60×/sec)
;
; Button read order is fixed by hardware: A, B, Select, Start, Up, Down, Left, Right
; Each read of $4016 clocks out the next button in bit 0 (1=pressed, 0=not).
; =============================================================================
.proc nmi_handler
    lda #$BF            ; default square wave duty cycle
    sta duty_cycle

    ; --- Strobe controller to latch all button states ---
    lda #$01
    sta $4016           ; strobe on
    lda #$00
    sta $4016           ; strobe off — buttons now clock out one at a time

    ; Clear per-frame state
    sta moving          ; $00 → moving
    sta note_index      ; $00 → note_index (C4 default, overwritten if pressed)

    lda $4016           ; A      — discard
    and #$01
    beq @no_a
        lda #$FF
        sta duty_cycle
    @no_a:

    lda $4016           ; B      — discard
    and #$01
    beq @no_b
        lda #$3F
        sta duty_cycle
    @no_b:

    lda $4016           ; Select — discard
    lda $4016           ; Start  — discard

    ; --- Read directions: move Sam and record which note to play ---
    ; note_index is set to the last pressed direction (Right wins if multiple held)

    ; Up → G4 (index 4)
    lda $4016
    and #$01
    beq @no_up
        dec sam_y
        lda #$01
        sta moving
        lda #$04
        sta note_index
@no_up:

    ; Down → A4 (index 5)
    lda $4016
    and #$01
    beq @no_down
        lda #$01
        sta moving
        lda #$05
        sta note_index

        inc sam_y
        lda sam_y
        cmp #$C0 ; carry set if sam_y >= $C0
        bcc @no_down ; carry clear = still above grass, ok
        lda #$BF ; past limit - snap back
        sta sam_y
@no_down:

    ; Left → E4 (index 2)
    lda $4016
    and #$01
    beq @no_left
        dec sam_x
        lda #$01
        sta moving
        lda #$02
        sta note_index
@no_left:

    ; Right → C4 (index 0)
    lda $4016
    and #$01
    beq @no_right
        inc sam_x
        lda #$01
        sta moving
        lda #$00
        sta note_index
@no_right:

    ; --- Sound timer: retrigger note every 16 frames while moving ---
    ; Movement and note_index are now known. Sound decision happens here.
    lda moving
    bne @is_moving
    jmp @silence        ; not moving — too far for beq, use invert+jmp
@is_moving:
        inc sound_timer
        lda sound_timer
        cmp #$10
        beq @timer_done
        jmp @skip_sound ; timer still counting — note keeps ringing, skip retrigger
@timer_done:
        lda #$00
        sta sound_timer
        ldx note_index
        lda duty_cycle
        sta $4000
        lda note_lo,x
        sta $4002
        lda note_hi,x
        ora #$08
        sta $4003
        jmp @skip_sound

@silence:
    lda #$00
    sta sound_timer
    sta $4000           ; silence

@skip_sound:

    ; --- Update shadow OAM: Y positions ---
    ; Sam is 3 rows of 2 sprites each, stacked 8px apart
    lda sam_y
    sta $0200           ; row 0 left  Y
    sta $0204           ; row 0 right Y
    clc
    adc #$08
    sta $0208           ; row 1 left  Y
    sta $020C           ; row 1 right Y
    clc
    adc #$08
    sta $0210           ; row 2 left  Y
    sta $0214           ; row 2 right Y

    ; --- Update shadow OAM: X positions ---
    lda sam_x
    sta $0203           ; row 0 left  X
    sta $020B           ; row 1 left  X
    sta $0213           ; row 2 left  X
    clc
    adc #$08
    sta $0207           ; row 0 right X
    sta $020F           ; row 1 right X
    sta $0217           ; row 2 right X

    ; --- Animation: cycle frames while moving, reset when still ---
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

    ; Update tile indices in shadow OAM for all 6 sprites
    lda anim_frame
    asl                 ; × 2 → offset into anim_tiles row
    tax

    lda anim_tiles,x    ; head tiles
    sta $0201
    inx
    lda anim_tiles,x
    sta $0205

    lda anim_frame
    asl
    clc
    adc #$04            ; body row offset
    tax

    lda anim_tiles,x
    sta $0209
    inx
    lda anim_tiles,x
    sta $020D

    lda anim_frame
    asl
    clc
    adc #$08            ; feet row offset
    tax

    lda anim_tiles,x
    sta $0211
    inx
    lda anim_tiles,x
    sta $0215

    ; --- DMA shadow OAM → PPU OAM ---
    lda #$00
    sta $2003
    lda #$02
    sta $4014

    rti

.endproc


; =============================================================================
; irq_handler — IRQs are disabled (SEI in reset), this never runs
; =============================================================================
.proc irq_handler
    rti
.endproc


; =============================================================================
; Interrupt vectors — hardware reads these on startup and interrupts
;   $FFFA  NMI vector
;   $FFFC  Reset vector
;   $FFFE  IRQ vector
; =============================================================================
.segment "VECTORS"
    .word nmi_handler
    .word reset_handler
    .word irq_handler
