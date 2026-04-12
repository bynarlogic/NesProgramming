.segment "HEADER"
    .byte $4E, $45, $53, $1A    ; "NES" + EOF marker (ASCII)
    .byte $02                   ; 2 PRG-ROM Banks (2 * 16Kb)
    .byte $01                   ; 1 CHR-ROM Bank (8kb)
    .byte $00                   ; Mapper 0, no mirroring flags
    .byte $00                   ; Mapper 0 (high nibble), standard iNES
    .byte $00, $00, $00, $00    ; Padding (bytes 8–11)
    .byte $00, $00, $00, $00    ; Padding (bytes 12–15)

.segment "CODE"

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUADDR   = $2006
PPUDATA   = $2007

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
    lda #$13
    sta PPUDATA

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