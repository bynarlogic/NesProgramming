; =============================================================================
; reset.s — reset handler (power-on and reset button entry point)
;
; The CPU jumps here on power-up and on reset via the vector at $FFFC.
; Job: get the hardware into a known state, load all PPU data, then
; hand off to the NMI-driven game loop by enabling NMI and spinning forever.
;
; STANDARD NES STARTUP SEQUENCE (don't deviate from this):
;   1. SEI     — disable IRQs (keep them off during init)
;   2. CLD     — disable decimal mode (BCD arithmetic; unused on NES)
;   3. TXS     — initialize stack pointer to $FF
;   4. Two VBlank waits — PPU needs ~29,780 cycles to warm up after power-on
;   5. Load palette, nametable, attribute data into PPU
;   6. Initialize shadow OAM (page $02)
;   7. Trigger initial OAM DMA
;   8. Write PPUSCROLL (MUST be after all PPUADDR writes, or scroll corrupts)
;   9. Enable rendering via PPUMASK
;  10. Enable APU channels
;  11. Enable NMI via PPUCTRL (this starts the game loop!)
;  12. Spin in @loop forever (game now runs entirely from NMI)
; =============================================================================

.segment "CODE"

.proc reset_handler

    sei                     ; disable IRQs — keep them off during initialization
    cld                     ; disable decimal mode (not implemented on NES 2A03)
    ldx #$FF
    txs                     ; stack pointer = $FF (stack is $0100-$01FF, grows down)

    ; --- Wait for PPU to warm up: two VBlank waits ---
    ; After power-on, the PPU needs time before it's safe to write its registers.
    ; We poll PPUSTATUS bit 7 (the VBlank flag) and wait for it to set twice.
    ; Reading PPUSTATUS also resets the PPUADDR write latch — good habit here.
@vblankwait1:
    bit PPUSTATUS           ; tests bit 7 without changing A; clears the VBlank flag
    bpl @vblankwait1        ; BPL = "branch if positive" = branch if bit 7 is 0

@vblankwait2:
    bit PPUSTATUS
    bpl @vblankwait2

    ; --- Load all 8 palettes (32 bytes) into PPU $3F00-$3F1F ---
    ; Reading PPUSTATUS here resets the PPUADDR latch before the two-write sequence.
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR             ; first write: high byte of PPU address
    lda #$00
    sta PPUADDR             ; second write: low byte → PPU now points to $3F00

    ldx #$00
@palette_loop:
    lda palette_data,X
    sta PPUDATA             ; auto-increments PPUADDR after each write
    inx
    cpx #$20                ; $20 = 32 bytes (4 BG palettes + 4 sprite palettes)
    bne @palette_loop

    ; --- Load attribute table into PPU $23C0-$23FF ---
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
    cpx #$40                ; $40 = 64 bytes (8 rows × 8 bytes = full nametable 0)
    bne @attr_loop

    ; --- Write grass tiles into the background nametable ---
    ; Nametable 0 starts at PPU $2000 (32 columns × 30 rows = 960 tiles).
    ; Rows 27-29 (Y≈216-231) use grass tiles to form the ground Sam walks on.

    ; Row 27 at PPU $2360 — grass top edge (tile $01)
    lda PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$60
    sta PPUADDR
    lda #$01                ; tile $01 = grass top edge (defined in CHARS_BG)
    ldx #$00
@row27:
    sta PPUDATA
    inx
    cpx #$20                ; 32 columns
    bne @row27

    ; Row 28 at PPU $2380 — grass fill (tile $02)
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

    ; Row 29 at PPU $23A0 — grass fill continued
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
    sta sam_x               ; center-ish horizontally
    lda #$B7
    sta sam_y               ; just above the grass floor

    ; --- Clear shadow OAM ($0200-$02FF) to $FF ---
    ; OAM Y positions >= $EF are off-screen on NTSC. Setting all slots to $FF
    ; hides every sprite. We then copy only Sam's 6 slots on top.
    ; This prevents garbage sprite data from showing as we update only Sam.
    lda #$FF
    ldx #$00
@clear_oam:
    sta $0200,X
    inx
    bne @clear_oam          ; X wraps $FF → $00, covering all 256 bytes of page $02

    ; --- Copy Sam's OAM template into shadow OAM ---
    ldx #$00
@sam_oam_loop:
    lda sam_oam,X
    sta $0200,X
    inx
    cpx #$18                ; $18 = 24 bytes (6 sprites × 4 bytes each)
    bne @sam_oam_loop

    ; --- Initial OAM DMA: sync shadow OAM to PPU before rendering starts ---
    lda #$00
    sta OAMADDR             ; reset OAM write cursor to slot 0
    lda #SHADOW_OAM_PAGE
    sta OAMDMA              ; triggers DMA from $0200-$02FF to PPU OAM

    ; --- Set scroll to (0,0) ---
    ; PPUSCROLL MUST be written after all PPUADDR writes. PPUSCROLL shares
    ; the PPUADDR write latch internally. If you write PPUSCROLL first and
    ; then write PPUADDR, the latch state gets mixed up and scroll glitches.
    lda #$00
    sta PPUSCROLL           ; X scroll = 0
    sta PPUSCROLL           ; Y scroll = 0 (yes, two writes — same register, same latch)

    ; --- Enable rendering ---
    lda #$1E                ; %00011110: show BG ($02) + show sprites ($10)
    sta PPUMASK             ;            + show left 8px of BG ($08) + sprites ($10)

    ; --- Enable APU Pulse 1 channel ---
    lda #$01
    sta APU_STATUS          ; bit 0 = Pulse 1 on

    lda #$08                ; sweep disabled; negate=1 avoids overflow silence at low freqs
    sta APU_PULSE1_SWEEP

    ; --- Enable NMI (this starts the game loop) ---
    ; Writing PPUCTRL last because the moment NMI is enabled, the next VBlank
    ; will fire nmi_handler. Everything above must be fully initialized first.
    ; Bit 7 = NMI enable. Bit 3 = sprites from pattern table $1000 (our chr).
    lda #$88                ; %10001000: NMI enable + sprite pattern table $1000
    sta PPUCTRL

    ; --- Spin forever — game runs entirely from NMI from here ---
@loop:
    jmp @loop

.endproc
