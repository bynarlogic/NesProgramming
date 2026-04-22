; =============================================================================
; sprite.s — Sam the Robot (Day 7: duty-cycle automation)
;
; TOP-LEVEL FILE — this is the entry point for the assembler.
; Its job is to define ROM segments and .include all other source files.
; Read it like a table of contents: you see WHAT the program contains,
; not HOW any of it works.
;
; BUILD COMMAND (unchanged from single-file):
;   ca65 sprite.s -o sprite.o && ld65 -C sprite.cfg sprite.o -o sprite.nes
;
; The .include directive splices each file in at assemble time — the assembler
; sees it all as one big file. Same result as copy-paste, but organized.
; No Makefile needed; no change to the build command.
;
; FILE MAP:
;   constants.inc  — hardware register equates (PPU, APU, controller)
;   zeropage.inc   — zero-page variable layout and addresses ($00-$07)
;   macros.inc     — assembler macros (play_note)
;   data.s         — ROM data: palettes, note tables, OAM template, anim tiles
;   reset.s        — power-on initialization (reset_handler)
;   nmi.s          — NMI handler + IRQ stub (game loop orchestrator)
;   player.s       — update_player, update_oam, update_animation subroutines
;   sound.s        — update_sound subroutine
;   sprite.cfg     — linker memory map: PRG-ROM, CHR-ROM, interrupt vectors
;
; NES MEMORY MAP (for reference):
;   CPU $0000-$00FF  Zero page (fast RAM — variables in zeropage.inc)
;   CPU $0100-$01FF  Stack
;   CPU $0200-$02FF  Shadow OAM (sprite staging, DMA'd to PPU each frame)
;   CPU $0300-$07FF  General RAM (unused)
;   CPU $8000-$FFFF  PRG-ROM (this program — 32KB on NROM-256)
;   PPU $0000-$0FFF  CHR-ROM pattern table 0 (background tiles)
;   PPU $1000-$1FFF  CHR-ROM pattern table 1 (sprite tiles — sam-robot.chr)
;   PPU $2000-$23FF  Nametable 0 (background tile map, 32×30)
;   PPU $3F00-$3F1F  Palette RAM (8 palettes × 4 colors)
; =============================================================================

; --- Include definitions first — no code or data bytes emitted yet ---
; .inc files are "headers": equates and macro definitions only.
; They must come before the code that uses them.
.include "constants.inc"    ; hardware register equates + game constants
.include "zeropage.inc"     ; zero-page variable layout
.include "macros.inc"       ; play_note macro (needs constants.inc for register names)

; =============================================================================
; iNES HEADER — 16 bytes at offset 0 in the .nes file
;
; Emulators and flashcarts read this before running the ROM to know:
; how much PRG-ROM and CHR-ROM exist, which mapper to use, and mirroring mode.
; The .cfg file maps the HEADER segment to the start of the output file.
; =============================================================================
.segment "HEADER"
    .byte $4E, $45, $53, $1A    ; "NES" + $1A: magic identifier (iNES format)
    .byte $02                   ; PRG-ROM: 2 × 16KB banks = 32KB total
    .byte $01                   ; CHR-ROM: 1 × 8KB bank
    .byte $00                   ; flags 6: mapper 0 (NROM), horizontal mirroring
    .byte $00                   ; flags 7: mapper 0 high nibble, standard iNES
    .byte $00, $00, $00, $00    ; padding bytes 8-11 (unused in iNES 1.0)
    .byte $00, $00, $00, $00    ; padding bytes 12-15

; =============================================================================
; CHR-ROM — tile graphics, burned into the cartridge as read-only data
;
; The PPU reads CHR-ROM directly for rendering. The CPU can only write to it
; if the game uses CHR-RAM (we're using CHR-ROM, so tiles are fixed at compile time).
;
; Two 4KB pattern tables:
;   CHARS_BG  ($0000-$0FFF in PPU) — background tile definitions
;   CHARS_SPR ($1000-$1FFF in PPU) — sprite tile definitions
;
; PPUCTRL bit 4 selects background pattern table (0=$0000, 1=$1000).
; PPUCTRL bit 3 selects sprite pattern table     (0=$0000, 1=$1000).
; We set PPUCTRL=$88: sprites from $1000, background from $0000.
;
; Each tile = 16 bytes (8×8 pixels, 2 bitplanes).
; Pixel color = (plane1_bit << 1) | plane0_bit  →  palette index 0-3.
; =============================================================================
.segment "CHARS_BG"

    ; Tile $00 — blank sky (all zeros = index 0 = universal background color)
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; bitplane 0
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; bitplane 1

    ; Tile $01 — grass top edge
    .byte $20,$AA,$76,$DD,$B7,$6D,$DB,$76   ; bitplane 0
    .byte $00,$00,$89,$22,$48,$92,$24,$89   ; bitplane 1

    ; Tile $02 — grass fill (repeating texture for rows below the top edge)
    .byte $D5,$AB,$76,$DD,$B7,$6D,$DB,$76   ; bitplane 0
    .byte $2A,$54,$89,$22,$48,$92,$24,$89   ; bitplane 1

.segment "CHARS_SPR"
    ; Sam the Robot sprite tiles — loaded from an external binary file.
    ; .incbin reads raw bytes from the file with no assembler interpretation.
    ; The file contains 512 bytes (32 tiles × 16 bytes each) for two walk frames.
    .incbin "sam-robot.chr"

; =============================================================================
; CODE — all game logic, included from separate files into the PRG-ROM segment
; =============================================================================
.segment "CODE"

.include "data.s"       ; ROM data tables (palettes, notes, OAM template, anim tiles)
.include "reset.s"      ; reset_handler — power-on entry point
.include "nmi.s"        ; nmi_handler + irq_handler
.include "player.s"     ; update_player, update_oam, update_animation
.include "sound.s"      ; update_sound

; =============================================================================
; INTERRUPT VECTORS — 6 bytes at $FFFA-$FFFF (required by 6502 hardware)
;
; On power-up and reset, the CPU reads $FFFC-$FFFD and jumps to that address.
; On NMI (VBlank), it reads $FFFA-$FFFB. On IRQ, it reads $FFFE-$FFFF.
; .word emits a 16-bit little-endian address (low byte first, then high byte).
;
; These are addresses, not code — just pointers to where the handlers live.
; =============================================================================
.segment "VECTORS"
    .word nmi_handler       ; $FFFA-$FFFB: NMI vector
    .word reset_handler     ; $FFFC-$FFFD: reset vector (CPU starts here)
    .word irq_handler       ; $FFFE-$FFFF: IRQ/BRK vector
