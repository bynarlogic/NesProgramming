; =============================================================================
; constants.inc — hardware register addresses and game-wide constants
;
; CONVENTION: Files ending in .inc are "header" files.
; They contain only definitions — no executable code, no data bytes emitted.
; Any .s file can .include this at the top to use these names.
;
; Equates (=) are assembler-time substitutions: the assembler replaces the
; name with the value wherever it appears. They don't allocate memory or
; emit any bytes into the ROM.
; =============================================================================

; ---------------------------------------------------------------------------
; PPU registers — mapped into CPU address space at $2000-$2007
; The PPU is the NES graphics chip. You talk to it through these addresses.
; ---------------------------------------------------------------------------
PPUCTRL   = $2000   ; Write: NMI enable (bit 7), sprite/BG pattern table select,
                    ;        sprite size, VRAM increment direction
PPUMASK   = $2001   ; Write: rendering enable — bit 1=show BG, bit 4=show sprites
                    ;        $1E = show both (standard)
PPUSTATUS = $2002   ; Read:  bit 7=VBlank flag (cleared on read)
                    ;        Reading this also resets the PPUADDR write latch
PPUADDR   = $2006   ; Write: set PPU VRAM address — TWO writes required,
                    ;        high byte first, then low byte
PPUDATA   = $2007   ; Read/Write: PPU memory at current PPUADDR
                    ;        Auto-increments address after each access

; --- OAM (sprite memory) access ---
OAMADDR   = $2003   ; Write: OAM byte offset before DMA (always write $00 first)
PPUSCROLL = $2005   ; Write: screen scroll — two writes, X scroll then Y scroll
                    ;        Shares the address latch with PPUADDR — write LAST

; --- DMA ---
OAMDMA    = $4014   ; Write: page number → triggers CPU RAM → PPU OAM DMA
                    ;        Write $02 to copy $0200-$02FF into PPU OAM
                    ;        CPU stalls for 513-514 cycles during the transfer

; ---------------------------------------------------------------------------
; APU registers — Audio Processing Unit
; The NES APU lives at $4000-$4017 in CPU address space.
; ---------------------------------------------------------------------------
APU_STATUS       = $4015  ; Write: channel enable flags
                          ;        bit 0 = Pulse 1, bit 1 = Pulse 2,
                          ;        bit 2 = Triangle, bit 3 = Noise, bit 4 = DMC
APU_PULSE1_CTRL  = $4000  ; Write: duty cycle (bits 7-6) + envelope settings
                          ;        bits 7-6: 00=12.5%  01=25%  10=50%  11=75%
                          ;        bit 5: length counter halt
                          ;        bit 4: constant volume (vs envelope decay)
                          ;        bits 3-0: volume (0-15)
APU_PULSE1_SWEEP = $4001  ; Write: sweep unit (write $08 to disable safely)
APU_PULSE1_LO    = $4002  ; Write: period low 8 bits
APU_PULSE1_HI    = $4003  ; Write: period high 3 bits (bits 2-0) +
                          ;        length counter load (bits 7-3)
                          ;        WARNING: writing this register ALWAYS retriggers the note

; ---------------------------------------------------------------------------
; Controller
; ---------------------------------------------------------------------------
CONTROLLER1 = $4016   ; Write $01 then $00 to strobe (latches all button states)
                      ; Then read bit 0 eight times, one button per read:
                      ; A, B, Select, Start, Up, Down, Left, Right

; ---------------------------------------------------------------------------
; Shadow OAM — the CPU-side staging area for sprite data
; ---------------------------------------------------------------------------
; Convention: page $02 ($0200-$02FF) is standard NES shadow OAM.
; Each frame, you update this CPU RAM, then DMA it to PPU OAM via $4014.
; The PPU can't directly read CPU RAM — the DMA is the bridge.
SHADOW_OAM_PAGE = $02

; ---------------------------------------------------------------------------
; Game timing constants
; ---------------------------------------------------------------------------
ANIM_RATE  = $10   ; Frames between animation flips (16 frames ≈ 4 flips/sec)
SOUND_RATE = $10   ; Frames between note retriggers while Sam is moving

; ---------------------------------------------------------------------------
; APU Pulse 1 duty cycle presets
;
; Full byte format for APU_PULSE1_CTRL:  DD_L_C_VVVV
;   DD   = duty: 00=12.5%  01=25%  10=50%  11=75%
;   L    = length counter halt (1 = hold note; don't let it auto-silence)
;   C    = constant volume (1 = use VVVV directly; 0 = use envelope decay)
;   VVVV = volume 0-15
;
; All three presets below: length halt=1, constant volume=1, volume=15 (max)
; Only the duty bits differ.
; ---------------------------------------------------------------------------
DUTY_12 = $3F   ; %00_1_1_1111 — 12.5% duty (thin, buzzy tone)
DUTY_50 = $BF   ; %10_1_1_1111 — 50%   duty (full square wave, neutral)
DUTY_75 = $FF   ; %11_1_1_1111 — 75%   duty (same timbre as 25%, phase-inverted)
