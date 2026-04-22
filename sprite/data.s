; =============================================================================
; data.s — ROM data tables
;
; All tables here live in the CODE segment (PRG-ROM). They're constants
; burned into the cartridge — the CPU can read them but not write to them.
;
; CONVENTION: Keep all data tables in one file, at the top of CODE, so
; they're easy to find and edit. The CPU never "falls into" this data
; because the reset vector ($FFFC) points to reset_handler — the CPU
; arrives there via the hardware vector, not by executing linearly from $8000.
;
; Tables are accessed with indexed addressing: LDA table_name,X
; X holds the byte offset from the start of the table label.
; =============================================================================

.segment "CODE"

; ---------------------------------------------------------------------------
; Palettes — 32 bytes total, written to PPU $3F00-$3F1F during init
;
; Layout: 4 background palettes (16 bytes), then 4 sprite palettes (16 bytes).
; Each palette is 4 bytes. Byte 0 of each BG palette is mirrored from $3F00
; (the universal background color) — writing it has no effect on BG palettes 1-3.
; ---------------------------------------------------------------------------
palette_data:
    ; Background palettes ($3F00-$3F0F)
    .byte $21, $1A, $08, $26    ; bg pal 0: sky blue / teal / brown / olive
    .byte $23, $1A, $28, $17    ; bg pal 1
    .byte $23, $14, $2C, $30    ; bg pal 2
    .byte $23, $11, $1C, $27    ; bg pal 3

    ; Sprite palettes ($3F10-$3F1F)
    ; Byte 0 of sprite palettes is "transparent" — the BG shows through
    .byte $FF, $11, $27, $10    ; spr pal 0
    .byte $21, $16, $37, $28    ; spr pal 1
    .byte $21, $06, $17, $28    ; spr pal 2
    .byte $0D, $16, $37, $07    ; spr pal 3

; ---------------------------------------------------------------------------
; Attribute table — 64 bytes, written to PPU $23C0-$23FF
;
; The attribute table assigns a palette to each 4×4 block of background tiles.
; Each byte covers four 2×2 sub-blocks (2 bits each).
; All zeros here means: every tile uses background palette 0.
; ---------------------------------------------------------------------------
attr_data:
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; ---------------------------------------------------------------------------
; Note period tables — C major scale, octave 2 (C2-C3)
;
; Period formula (NTSC): period = 1,789,773 / (16 × freq) - 1
; The 11-bit result is split across two APU registers:
;   APU_PULSE1_LO = low 8 bits
;   APU_PULSE1_HI bits 2-0 = high 3 bits
;
; Index:    0     1     2     3     4     5     6     7
; Note:     C2    D2    E2    F2    G2    A2    B2    C3
; Freq(Hz): 65    73    82    87    98   110   123   131
; Period: 1709  1523  1357  1280  1140  1016   905   854
; ---------------------------------------------------------------------------
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

; ---------------------------------------------------------------------------
; Directional note tables — four notes stacked in perfect 4ths
;
; Starting from C2, each note is a perfect 4th (5 semitones) above the last.
; Period formula (NTSC): period = 1,789,773 / (16 × freq) - 1
;
; Index:    0      1      2      3
; Note:     C2     F2     Bb2    Eb3
; Freq(Hz): 65.4   87.3   116.5  155.6
; Period:   1709   1280    959    718
;
; Used by update_sound and assigned by update_player:
;   0 = Down  (C2,  lowest)
;   1 = Right (F2,  a 4th above Down)
;   2 = Left  (Bb2, a 4th above Right)
;   3 = Up    (Eb3, a 4th above Left, highest)
; ---------------------------------------------------------------------------
dir_note_lo:
    .byte $AD   ; C2  period = $06AD
    .byte $00   ; F2  period = $0500
    .byte $BF   ; Bb2 period = $03BF
    .byte $CE   ; Eb3 period = $02CE

dir_note_hi:
    .byte $06   ; C2
    .byte $05   ; F2
    .byte $03   ; Bb2
    .byte $02   ; Eb3

; ---------------------------------------------------------------------------
; Sam's OAM template — 6 sprite entries, 4 bytes each = 24 bytes
;
; OAM entry byte order: Y position, tile index, attributes, X position
;
; Sam is a 2×3 grid of 8×8 pixel sprites:
;   [head_L][head_R]   ← row 0
;   [body_L][body_R]   ← row 1
;   [feet_L][feet_R]   ← row 2
;
; These are INITIAL values copied to shadow OAM at startup. The NMI handler
; overwrites Y and X every frame; tile indices are rewritten by update_animation.
;
; Attribute byte bits:
;   bit 7 = flip vertical, bit 6 = flip horizontal
;   bits 1-0 = sprite palette select (0-3)
; ---------------------------------------------------------------------------
sam_oam:
    ;        Y     tile  attr   X
    .byte $B7, $00, $00, $78   ; row 0: head left
    .byte $B7, $01, $00, $80   ; row 0: head right
    .byte $BF, $10, $00, $78   ; row 1: body left
    .byte $BF, $11, $00, $80   ; row 1: body right
    .byte $C7, $20, $00, $78   ; row 2: feet left
    .byte $C7, $21, $00, $80   ; row 2: feet right

; ---------------------------------------------------------------------------
; Walk cycle tile indices — 2 animation frames × 3 rows × 2 tiles
;
; Layout: [row0_f0L, row0_f0R, row0_f1L, row0_f1R,
;          row1_f0L, row1_f0R, row1_f1L, row1_f1R,
;          row2_f0L, row2_f0R, row2_f1L, row2_f1R]
;
; Index formula (used by update_animation):
;   base  = anim_frame * 2         (0 for frame 0, 2 for frame 1)
;   head  = base + 0               (offset 0 into table)
;   body  = base + 4               (offset 4 into table)
;   feet  = base + 8               (offset 8 into table)
; ---------------------------------------------------------------------------
anim_tiles:
    .byte $00, $01, $02, $03    ; head row: [f0_left, f0_right, f1_left, f1_right]
    .byte $10, $11, $12, $13    ; body row
    .byte $20, $21, $22, $23    ; feet row
