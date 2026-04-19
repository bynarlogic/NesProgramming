.segment "HEADER"
    .byte $4E, $45, $53, $1A    ; "NES" + EOF marker (ASCII)
    .byte $02                   ; 2 PRG-ROM Banks (2 * 16Kb)
    .byte $01                   ; 1 CHR-ROM Bank (8kb)
    .byte $00                   ; Mapper 0, no mirroring flags
    .byte $00                   ; Mapper 0 (high nibble), standard iNES
    .byte $00, $00, $00, $00    ; Padding (bytes 8–11)
    .byte $00, $00, $00, $00    ; Padding (bytes 12–15)

.segment "CHARS"
  ; Tile 0 — blank
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 0
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 1

  ; Tile 1 — face
  .byte $3C, $7E, $C6, $FE, $FE, $EE, $C6, $7C  ; plane 0
  .byte $3C, $42, $92, $82, $82, $92, $82, $7C  ; plane 1

  ; Tile 2 — hollow box
  .byte $FF, $81, $81, $81, $81, $81, $81, $FF  ; plane 0
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 1

  ; Tile 3 — checkerboard
  .byte $00, $00, $00, $00, $00, $00, $00, $00  ; plane 0
  .byte $AA, $55, $AA, $55, $AA, $55, $AA, $55  ; plane 1


.segment "CODE"

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUADDR   = $2006
PPUDATA   = $2007

palette_data:
    .byte $0F, $16, $22, $30    ; palette 0: red / blue / white
    .byte $23, $1A, $28, $17    ; palette 1: green / yellow / orange
    .byte $23, $14, $2C, $30    ; palette 2: purple / pink / white
    .byte $23, $11, $1C, $27    ; palette 3: teal / lime / gold

attr_data:
    ; 8 bytes covering the full top row of 4×4 blocks ($23C0–$23C7)
    ; $00=all pal0  $55=all pal1  $AA=all pal2  $FF=all pal3
    .byte $00, $55, $AA, $FF, $00, $55, $AA, $FF

.proc reset_handler
    sei           ; disable IRQs
    cld           ; disable decimal mode (not used on NES)
    ldx #$FF      ; load the valuel 255 into the X register
    txs           ; transfer X to the stack pointer
    ; Wait for first VBlank
@vblankwait1:
    bit PPUSTATUS       ; test bit 7 of $2002
    bpl @vblankwait1    ; loop if bit 7 is 0 (not VBlank yet)

    ; Wait for second VBlank
@vblankwait2:
    bit PPUSTATUS
    bpl @vblankwait2


    ; reset the address latch first (always do this)
    bit PPUSTATUS

    ; point PPU at $3F00 (background palette)
    lda #$3F
    sta PPUADDR     ; high byte
    lda #$00
    sta PPUADDR     ; low byte

    ; write a color
    ldx #$00                ; start at index 0
@palette_loop:
    lda palette_data,X      ; load lthe byte at palette_data + X
    sta PPUDATA             ; write it to the PPU
    inx                     ; X = X + 1
    cpx #$10                ; written 16 bytes? (4 palettes × 4 bytes)
    bne @palette_loop       ; =if not, loop back (branch if not equal)

    ; Write tile 0 to top-left of nametable
    LDA PPUSTATUS       ; reset address latch
    LDA #$20
    STA PPUADDR         ; high byte
    LDA #$00
    STA PPUADDR         ; low byte = $2000

    LDX #$00
@tile_loop:
    LDA #$01            ; face tile
    STA PPUDATA
    INX
    CPX #$80            ; 128 tiles = 4 rows (32×4)
    BNE @tile_loop

    ; Write attribute table — 8 bytes, covers columns 0–31 rows 0–3
    LDA PPUSTATUS
    LDA #$23
    STA PPUADDR
    LDA #$C0
    STA PPUADDR

    LDX #$00
@attr_loop:
    LDA attr_data,X
    STA PPUDATA
    INX
    CPX #$08
    BNE @attr_loop

    ; Set scroll LAST — after all PPUADDR writes, before PPUMASK
    lda #$00
    sta $2005           ; X scroll = 0
    sta $2005           ; Y scroll = 0

    ; enable background rendering
    lda #$0A
    sta PPUMASK

    ; loop forever
@loop:
    jmp @loop

.endproc


.proc nmi_handler
    rti
.endproc

.proc irq_handler
    rti
.endproc

.segment "VECTORS"
    .word nmi_handler    ; $FFFA
    .word reset_handler  ; $FFFC
    .word irq_handler    ; $FFFE

.segment "CHARS"
    ; empty CHR-ROM — 8KB of zeros (filled automatically)