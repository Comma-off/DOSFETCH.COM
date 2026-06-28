; DOSFETCH - DOS System Fetch Utility
; NASM syntax, 16-bit real mode, .COM format
; Colors via INT 10h AH=09h (BIOS write char+attr, no ANSI.SYS needed)

        bits    16
        org     100h

start:
        call    parse_cmdline

        ; /? → help then exit (before any detection)
        cmp     byte [flag_help], 1
        je      .show_help

        ; INT 10h AH=0Fh: get current video mode (AL = mode number)
        ; Text modes: 00h-03h, 07h. Anything else: disable colors to avoid
        ; garbled output in graphics modes.
        mov     ah, 0Fh
        int     10h
        cmp     al, 07h
        je      .mode_ok
        cmp     al, 03h
        jbe     .mode_ok
        mov     byte [flag_color], 0
.mode_ok:

        ; INT 21h AH=30h: AL=major, AH=minor, BH=OEM
        ; OEM: FDh=FreeDOS, EEh/EDh=DR-DOS, 66h=PTS-DOS, 00h=PC-DOS, FFh=MS-DOS
        mov     ah, 30h
        int     21h
        mov     [dos_major], al
        mov     [dos_minor], ah

        cmp     bh, 0FDh
        je      .os_free
        cmp     bh, 0EEh
        je      .os_dr
        cmp     bh, 0EDh
        je      .os_dr
        cmp     bh, 66h
        je      .os_pts
        cmp     bh, 00h
        je      .os_pc
        mov     word [os_ptr], str_msdos
        jmp     .os_done
.os_free:  mov word [os_ptr], str_freedos
           jmp .os_done
.os_dr:    mov word [os_ptr], str_drdos
           jmp .os_done
.os_pts:   mov word [os_ptr], str_ptsdos
           jmp .os_done
.os_pc:    mov word [os_ptr], str_pcdos
.os_done:

        ; CPU detection
        call    detect_cpu
        mov     [cpu_type], ax

        ; FPU
        call    detect_fpu
        mov     [fpu_type], al

        ; CPUID info (only on Pentium+)
        cmp     word [cpu_type], 4
        jl      .skip_cpuid
        call    get_cpuid_info
.skip_cpuid:

        ; BIOS date, machine type, and manufacturer
        call    get_bios_info
        call    get_bios_vendor

        ; Current drive letter
        mov     ah, 19h
        int     21h
        add     al, 'A'
        mov     [drv_ltr], al

        ; Volume label for current drive
        call    get_label

        ; Disk space (tries FAT32-aware 7303h first, falls back to 36h)
        call    get_disk_space

        ; RAM
        call    get_ram

        ; /I = info only, skip logo
        cmp     byte [flag_infoonly], 1
        je      .info_only

        ; ── Full display ──────────────────────────────────────
.full:
        call    print_crlf

%macro  logo_info 4             ; l_d, l_o, l_s, info_proc
        mov     word [ld], %1
        mov     word [lo], %2
        mov     word [ls], %3
        call    print_logo_line
        call    %4
        call    print_crlf
%endmacro

%macro  logo_blank 3
        mov     word [ld], %1
        mov     word [lo], %2
        mov     word [ls], %3
        call    print_logo_line
        call    print_crlf
%endmacro

        logo_blank l1d, l1o, l1s
        logo_info  l2d, l2o, l2s, print_os_info
        logo_info  l3d, l3o, l3s, print_cpu_info
        logo_info  l4d, l4o, l4s, print_fpu_info
        logo_info  l5d, l5o, l5s, print_model_info
        logo_info  l6d, l6o, l6s, print_disk_info
        logo_info  l7d, l7o, l7s, print_ram_info
        logo_info  l8d, l8o, l8s, print_bios_info

        call    print_crlf
        mov     ax, 4C00h
        int     21h

        ; ── Info-only display (/I) ────────────────────────────
.info_only:
        call    print_crlf
%macro  info_line 1
        call    %1
        call    print_crlf
%endmacro
        info_line print_os_info
        info_line print_cpu_info
        info_line print_fpu_info
        info_line print_model_info
        info_line print_disk_info
        info_line print_ram_info
        info_line print_bios_info
        call    print_crlf
        mov     ax, 4C00h
        int     21h

        ; ── Help display (/?) ─────────────────────────────────
.show_help:
        mov     si, str_help
        call    print_str
        mov     ax, 4C00h
        int     21h

; ============================================================
; print_os_info   – "  OS  : <name> <major>.<minor>"
; print_cpu_info  – "  CPU : <type>"
; print_disk_info – "  Disk: <free>MB / <total>MB (<drv>:, <label>)"
; print_ram_info  – "  RAM : <free>KB / <total>KB"
; (none emit CRLF; caller does that)
; ============================================================
print_os_info:
        mov     si, lbl_os
        call    print_str
        mov     si, [os_ptr]
        call    print_str
        mov     dl, ' '
        call    putchar
        mov     al, [dos_major]
        call    print8
        mov     dl, '.'
        call    putchar
        mov     al, [dos_minor]
        call    print8
        ret

print_cpu_info:
        mov     si, lbl_cpu
        call    print_str
        mov     bx, [cpu_type]
        shl     bx, 1
        mov     si, [cpu_tbl + bx]
        call    print_str
        ret

print_disk_info:
        mov     si, lbl_disk
        call    print_str
        mov     ax, [free_mb]
        call    print16
        mov     si, str_mb_of
        call    print_str
        mov     ax, [total_mb]
        call    print16
        mov     si, str_mb
        call    print_str
        mov     si, str_lp          ; " ("
        call    print_str
        mov     dl, [drv_ltr]
        call    putchar
        mov     dl, ':'
        call    putchar
        cmp     byte [label_buf], 0
        je      .close
        mov     si, str_comma
        call    print_str
        mov     si, label_buf
        call    print_str
.close:
        mov     dl, ')'
        call    putchar
        ret

print_ram_info:
        mov     si, lbl_ram
        call    print_str
        mov     ax, [ram_free_kb]
        call    print16
        mov     si, str_kb_of
        call    print_str
        mov     ax, [ram_total_kb]
        call    print16
        mov     si, str_kb
        call    print_str
        ret

print_fpu_info:
        mov     si, lbl_fpu
        call    print_str
        xor     bh, bh
        mov     bl, [fpu_type]
        shl     bx, 1
        mov     si, [fpu_tbl + bx]
        call    print_str
        ret

print_model_info:
        mov     si, lbl_model
        call    print_str
        cmp     word [cpu_type], 4
        jl      .na
        mov     si, cpu_vendor
        call    print_str
        mov     si, str_f_sep
        call    print_str
        mov     al, [cpu_family]
        call    print8
        mov     dl, 'M'
        call    putchar
        mov     al, [cpu_model_num]
        call    print8
        cmp     byte [has_tsc], 1
        jne     .done
        mov     si, str_tsc_yes
        call    print_str
.done:  ret
.na:    mov     si, str_na
        call    print_str
        ret

print_bios_info:
        mov     si, lbl_bios
        call    print_str
        mov     si, bios_vendor     ; e.g. "SeaBIOS"
        call    print_str
        mov     dl, ' '
        call    putchar
        mov     si, bios_date       ; e.g. "06/23/99"
        call    print_str
        mov     si, str_lp          ; " ("
        call    print_str
        mov     al, [machine_type]
        call    print_hex_byte
        mov     dl, 'h'
        call    putchar
        mov     dl, ')'
        call    putchar
        ret

; print_hex_byte: print AL as two uppercase hex digits
print_hex_byte:
        push    ax
        push    dx
        mov     ah, al              ; save in AH (putchar restores AX, so AH survives)
        shr     al, 4
        call    .nib
        mov     al, ah
        and     al, 0Fh
        call    .nib
        pop     dx
        pop     ax
        ret
.nib:   add al, '0'
        cmp al, '0'+10
        jl  .p
        add al, 7
.p:     mov dl, al
        call putchar
        ret

; ============================================================
; print_logo_line
; Checks flag_color: if set, uses INT 10h colored output;
; otherwise falls back to plain print_str.
; ============================================================
print_logo_line:
        push    si
        push    bx
        cmp     byte [flag_color], 0
        je      .plain

        mov     bl, 0Ch             ; bright red   (D)
        mov     si, [ld]
        call    print_colored
        mov     bl, 0Dh             ; bright magenta (O)
        mov     si, [lo]
        call    print_colored
        mov     bl, 0Eh             ; yellow (S)
        mov     si, [ls]
        call    print_colored
        jmp     .done

.plain:
        mov     si, [ld]
        call    print_str
        mov     si, [lo]
        call    print_str
        mov     si, [ls]
        call    print_str

.done:
        pop     bx
        pop     si
        ret

; ============================================================
; print_colored: print null-terminated string at SI with
; CGA color attribute in BL, using BIOS INT 10h.
; INT 10h AH=09h writes char+attr at cursor without advancing;
; we advance DL manually and reposition with AH=02h.
; ============================================================
print_colored:
        push    ax
        push    cx
        push    dx
        mov     [.attr], bl
        mov     ah, 03h
        xor     bh, bh
        int     10h                 ; DH=row, DL=col
.lp:
        lodsb
        test    al, al
        jz      .done
        mov     ah, 09h
        xor     bh, bh
        mov     bl, [.attr]
        mov     cx, 1
        int     10h
        inc     dl
        mov     ah, 02h
        xor     bh, bh
        int     10h
        jmp     .lp
.done:
        pop     dx
        pop     cx
        pop     ax
        ret
.attr   db 0

; ============================================================
; parse_cmdline: scan PSP command tail for /I and /C on|off
; PSP+80h = length, PSP+81h = text (not null-terminated)
; Defaults: flag_color=1 (on), flag_infoonly=0
; ============================================================
parse_cmdline:
        push    ax
        push    cx
        push    si

        mov     cl, [80h]           ; command line length
        xor     ch, ch
        test    cx, cx
        jz      .done

        mov     si, 81h             ; start of command tail

.scan:
        jcxz    .done
        lodsb
        dec     cx
        cmp     al, '/'
        jne     .scan

        jcxz    .done
        lodsb
        dec     cx
        cmp     al, '?'             ; /? (check before lowercasing — '?' unaffected anyway)
        je      .set_help
        or      al, 20h             ; to lowercase
        cmp     al, 'i'
        je      .set_I
        cmp     al, 'c'
        je      .parse_C
        jmp     .scan

.set_help:
        mov     byte [flag_help], 1
        jmp     .scan

.set_I:
        mov     byte [flag_infoonly], 1
        jmp     .scan

.parse_C:
        ; Skip leading spaces before "on"/"off"
.skip_sp:
        jcxz    .done
        lodsb
        dec     cx
        cmp     al, ' '
        je      .skip_sp

        or      al, 20h
        cmp     al, 'o'
        jne     .scan               ; not "o..." → ignore

        jcxz    .done
        lodsb
        dec     cx
        or      al, 20h

        cmp     al, 'n'             ; "on"
        je      .color_on
        cmp     al, 'f'             ; "of..." → check for "off"
        jne     .scan

        jcxz    .done
        lodsb
        dec     cx
        or      al, 20h
        cmp     al, 'f'             ; "off"
        jne     .scan
        mov     byte [flag_color], 0
        jmp     .scan

.color_on:
        mov     byte [flag_color], 1
        jmp     .scan

.done:
        pop     si
        pop     cx
        pop     ax
        ret

; ============================================================
; get_label: find volume label of current drive via INT 21h 4Eh
; Result null-terminated in label_buf (empty string if none)
; ============================================================
get_label:
        push    ax
        push    cx
        push    dx
        push    si
        push    di

        ; Patch drive letter into search path
        mov     al, [drv_ltr]
        mov     [srch_path], al

        ; Set DTA to our buffer
        mov     ah, 1Ah
        mov     dx, label_dta
        int     21h

        ; Find first with volume-label attribute (08h)
        mov     ah, 4Eh
        mov     cx, 08h
        mov     dx, srch_path
        int     21h
        jc      .nolabel

        ; Copy label from DTA filename field (offset 1Eh), max 11 chars
        mov     si, label_dta + 1Eh
        mov     di, label_buf
        mov     cx, 11
.cplp:
        lodsb
        test    al, al
        jz      .term
        cmp     al, ' '             ; stop at padding space
        je      .term
        cmp     al, '.'             ; skip 8.3 dot separator
        je      .skipdot
        stosb
        loop    .cplp
        jmp     .term
.skipdot:
        loop    .cplp
.term:
        mov     byte [di], 0
        jmp     .done
.nolabel:
        mov     byte [label_buf], 0
.done:
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     ax
        ret

; ============================================================
; get_ram: fills ram_total_kb (INT 12h) and ram_free_kb
; Free = largest free paragraph block (INT 21h 48h) × 16 / 1024
; ============================================================
get_ram:
        push    ax
        push    bx
        push    dx

        int     12h                 ; AX = total conventional KB
        mov     [ram_total_kb], ax

        ; Request impossibly large block → returns BX = max free paragraphs
        mov     ah, 48h
        mov     bx, 0FFFFh
        int     21h
        ; BX = max free paragraphs; KB = paragraphs * 16 / 1024 = paragraphs / 64
        mov     ax, bx
        xor     dx, dx
        mov     bx, 64
        div     bx
        mov     [ram_free_kb], ax

        pop     dx
        pop     bx
        pop     ax
        ret

; ============================================================
; get_disk_space: fills [free_mb] and [total_mb]
;
; First tries INT 21h AX=7303h (FAT32-aware, 32-bit cluster counts,
; available on FreeDOS and Win9x). Falls back to AH=36h on older DOS
; where 7303h is absent (CF set) or cluster counts fit in 16 bits.
;
; AH=36h caps returned counts at 0FFFFh on large FAT32 drives,
; producing wrong MB values; 7303h avoids this.
; ============================================================
get_disk_space:
        push    es
        push    ds
        pop     es                  ; ES = DS (COM: single segment)

        ; Prepare 44-byte DISKFREESPACE buffer
        mov     di, dfs_buf
        mov     word [dfs_buf],   44
        mov     word [dfs_buf+2],  0

        mov     ax, 7303h
        xor     dl, dl              ; 0 = current drive
        mov     cx, 44
        int     21h
        pop     es
        jc      .fallback           ; CF=1: not supported, use 36h

        call    calc_from_dfs
        ret

.fallback:
        mov     ah, 36h
        xor     dl, dl
        int     21h
        cmp     ax, 0FFFFh
        je      .invalid
        call    calc_mb             ; AX=spc, BX=free_cl, CX=bps, DX=total_cl
        ret

.invalid:
        mov     word [free_mb],  0
        mov     word [total_mb], 0
        ret

; ============================================================
; calc_from_dfs: fills [free_mb] and [total_mb] from dfs_buf
;   +00h dword: size   +04h: spc   +08h: bps
;   +0Ch dword: free_cl            +10h: total_cl
;
; mb = (cl_hi × spc_scaled × 32) + ((cl_lo × spc_scaled) >> 11)
; where spc_scaled = spc × (bps >> 9)
; Caps at 0FFFFh (≈64 TB) on overflow.
; ============================================================
calc_from_dfs:
        push    ax
        push    bx
        push    cx
        push    si

        ; spc_scaled: move bps to AX first so MOV CL,9 doesn't clobber CX
        mov     ax, [dfs_buf+8]     ; AX = bps (low word)
        mov     cl, 9
        shr     ax, cl              ; AX = bps >> 9 (1/2/4/8 for 512-4096 bps)
        mov     cx, ax              ; CX = bps_f
        mov     ax, [dfs_buf+4]     ; AX = spc (low word)
        mul     cx                  ; AX = spc_scaled
        mov     si, ax

        ; free_mb — low clusters
        mov     ax, [dfs_buf+0Ch]   ; free_cl low word
        mul     si
        mov     bx, dx
        mov     cl, 11
        shr     ax, cl
        mov     cl, 5
        shl     bx, cl
        add     ax, bx
        mov     [free_mb], ax

        ; free_mb — high clusters (× spc_scaled × 32)
        mov     ax, [dfs_buf+0Eh]   ; free_cl high word
        test    ax, ax
        jz      .fhi_done
        mul     si                  ; DX:AX = hi × spc_scaled
        test    dx, dx
        jnz     .fhi_cap
        mov     cl, 5
        shl     ax, cl
        jc      .fhi_cap
        add     [free_mb], ax
        jnc     .fhi_done
.fhi_cap:   mov word [free_mb], 0FFFFh
.fhi_done:

        ; total_mb — low clusters
        mov     ax, [dfs_buf+10h]
        mul     si
        mov     bx, dx
        mov     cl, 11
        shr     ax, cl
        mov     cl, 5
        shl     bx, cl
        add     ax, bx
        mov     [total_mb], ax

        ; total_mb — high clusters
        mov     ax, [dfs_buf+12h]
        test    ax, ax
        jz      .thi_done
        mul     si
        test    dx, dx
        jnz     .thi_cap
        mov     cl, 5
        shl     ax, cl
        jc      .thi_cap
        add     [total_mb], ax
        jnc     .thi_done
.thi_cap:   mov word [total_mb], 0FFFFh
.thi_done:

        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

; ============================================================
; detect_cpu -> AX: 0=8086  1=286  2=386  3=486  4=Pentium+(CPUID)
;
; 8086 : FLAGS bits 12-15 stuck at 1
; 286  : FLAGS bits 12-15 stuck at 0
; 386  : EFLAGS bit 18 (AC) stuck at 0
; 486  : EFLAGS bit 18 writable, bit 21 (ID) stuck at 0
; Pent+: EFLAGS bit 21 toggleable → CPUID available
;
; o32 pushf/popf access 32-bit EFLAGS; two 16-bit pops split into
; AX=low word (bits 0-15) and DX=high word (bits 16-31).
; ============================================================
detect_cpu:
        push    bx
        push    dx

        ; 8086: bits 12-15 of FLAGS always 1
        pushf
        pushf
        pop     ax
        and     ax, 0FFFh
        push    ax
        popf
        pushf
        pop     ax
        popf
        and     ax, 0F000h
        cmp     ax, 0F000h
        jne     .not_8086
        xor     ax, ax              ; 0 = 8086
        jmp     .done

.not_8086:
        ; 286: bits 12-15 of FLAGS always 0
        pushf
        pushf
        pop     ax
        or      ax, 0F000h
        push    ax
        popf
        pushf
        pop     ax
        popf
        and     ax, 0F000h
        jnz     .not_286
        mov     ax, 1               ; 1 = 286
        jmp     .done

.not_286:
        ; 386 vs 486+: try to set EFLAGS bit 18 (AC)
        ; o32 PUSHF/POPF via explicit 66h byte — NASM strips o32 on pushf in 16-bit mode.
        ; 66h 9Ch = PUSHFD; 66h 9Dh = POPFD.
        ; pop ax (low 16 of EFLAGS), pop dx (high 16, bits 16-31).
        ; Bit 18 of EFLAGS = bit 2 of dx.
        db 66h
        pushf                       ; save 32-bit EFLAGS
        db 66h
        pushf
        pop     ax
        pop     dx
        mov     bx, dx
        or      dx, 0004h           ; set bit 18
        push    dx
        push    ax
        db 66h
        popf
        db 66h
        pushf
        pop     ax
        pop     dx
        db 66h
        popf
        test    dx, 0004h
        jz      .is_386

        ; 486 vs Pentium+: toggle EFLAGS bit 21 (ID)
        ; bit 21 = bit 5 of dx (high word)
        db 66h
        pushf
        db 66h
        pushf
        pop     ax
        pop     dx
        mov     bx, dx
        xor     dx, 0020h
        push    dx
        push    ax
        db 66h
        popf
        db 66h
        pushf
        pop     ax
        pop     dx
        db 66h
        popf
        xor     dx, bx
        test    dx, 0020h
        jz      .is_486
        mov     ax, 4
        jmp     .done

.is_486: mov ax, 3                  ; 3 = 486
         jmp .done
.is_386: mov ax, 2                  ; 2 = 386

.done:
        pop     dx
        pop     bx
        ret

; ============================================================
; get_bios_vendor: fills bios_vendor[].
;
; Step 1 — SMBIOS: scan F000h:0000-FFE0 at 16-byte intervals for "_SM_".
;   Validate checksum, locate Type-0 BIOS structure, read Vendor string.
;   Only works when SMBIOS table is below 1MB (almost always on DOS).
;
; Step 2 — ROM scan: if SMBIOS fails, walk the entire F000h segment
;   (0000h-FF00h) looking for substrings in bios_pat_tbl.
;   Previously E000h-EF00h was too narrow; SeaBIOS places its string
;   outside that window.
; ============================================================
get_bios_vendor:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es

        mov     ax, 0F000h
        mov     es, ax

        ; ── Step 1: SMBIOS anchor scan ──────────────────────────
        ; SI = current paragraph offset (SI is a valid 16-bit base for [es:si+N])
        xor     si, si
.sm_scan:
        cmp     si, 0FFE0h
        jae     .rom_scan
        cmp     word [es:si],   '_S'
        jne     .sm_next
        cmp     word [es:si+2], 'M_'
        jne     .sm_next

        ; Validate entry-point checksum over [es:si .. si+len)
        xor     al, al
        mov     cl, [es:si+5]       ; entry-point length
        xor     ch, ch
        mov     bx, si
.sm_ck: add     al, [es:bx]
        inc     bx
        loop    .sm_ck
        test    al, al
        jnz     .sm_next            ; bad checksum

        ; Table address at +18h (dword). Skip if table is above 1MB.
        cmp     word [es:si+1Ah], 0
        jne     .sm_next
        mov     bx, [es:si+18h]     ; low word of physical table address
        mov     ax, bx
        shr     ax, 4               ; segment
        and     bx, 0Fh             ; offset within segment
        push    es
        mov     es, ax

        ; Walk SMBIOS structures looking for Type 0 (BIOS Information)
.sm_walk:
        cmp     byte [es:bx], 0     ; Type 0?
        je      .sm_type0
        cmp     byte [es:bx], 0FFh  ; end-of-table marker
        je      .sm_no
        xor     cx, cx
        mov     cl, [es:bx+1]       ; structure length
        add     bx, cx              ; skip fixed part → string table
.sm_skip:
        cmp     word [es:bx], 0     ; double-NUL = end of string table
        je      .sm_end
        inc     bx
        jmp     .sm_skip
.sm_end:
        add     bx, 2
        jmp     .sm_walk

.sm_type0:
        mov     cl, [es:bx+4]       ; vendor string index (1-based)
        xor     ch, ch
        test    cx, cx
        jz      .sm_no
        xor     ax, ax
        mov     al, [es:bx+1]       ; structure length
        add     bx, ax              ; BX → first byte of string table
        dec     cx                  ; make 0-based; 0 = already at right string
        jz      .sm_got
.sm_find:
        cmp     byte [es:bx], 0
        je      .sm_next_str
        inc     bx
        jmp     .sm_find
.sm_next_str:
        inc     bx
        loop    .sm_find
.sm_got:
        mov     di, bios_vendor
        mov     cx, 15
.sm_cp: mov     al, [es:bx]
        test    al, al
        jz      .sm_cp_done
        cmp     al, 20h
        jb      .sm_cp_done
        mov     [di], al
        inc     di
        inc     bx
        loop    .sm_cp
.sm_cp_done:
        mov     byte [di], 0
        pop     es
        ; Only accept SMBIOS result if at least one char was copied.
        ; If the vendor string was empty / all non-printable, fall
        ; through to the ROM scan which previously found "SeaBIOS".
        cmp     di, bios_vendor
        jne     .done
        ; Empty result — try ROM scan as fallback
        jmp     .rom_scan

.sm_no:     pop     es
.sm_next:   add     si, 10h
            jmp     .sm_scan

        ; ── Step 2: ROM string scan (whole segment) ──────────────
.rom_scan:
        mov     ax, 0F000h
        mov     es, ax
        xor     dx, dx              ; start at offset 0

.outer:
        cmp     dx, 0FF00h          ; stop before date/type area
        jae     .unknown

        mov     si, bios_pat_tbl

.try_pat:
        mov     cl, [si]
        test    cl, cl
        jz      .next_byte
        xor     ch, ch
        push    si
        push    cx
        inc     si
        mov     bx, dx
.cmp:   mov     al, [es:bx]
        cmp     al, [si]
        jne     .fail
        inc     bx
        inc     si
        loop    .cmp
        pop     cx
        pop     si
        mov     di, bios_vendor
        mov     bx, dx
        mov     cx, 15
.copy:  mov     al, [es:bx]
        cmp     al, 20h
        jb      .copy_done
        cmp     al, 7Eh
        ja      .copy_done
        mov     [di], al
        inc     di
        inc     bx
        loop    .copy
.copy_done:
        mov     byte [di], 0
        jmp     .done
.fail:  pop     cx
        pop     si
        add     si, cx
        inc     si
        jmp     .try_pat
.next_byte:
        inc     dx
        jmp     .outer

.unknown:
        mov     si, str_bios_unk
        mov     di, bios_vendor
.ucopy: lodsb
        stosb
        test    al, al
        jnz     .ucopy

.done:
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ============================================================
; detect_fpu -> AL: 0=none 1=8087 2=80287 3=80387 4=built-in
; Uses FNINIT+FNSTSW: if no FPU, fpu_sw stays 0FFFFh.
; FPU type inferred from cpu_type tier.
; ============================================================
detect_fpu:
        mov     word [fpu_sw], 0FFFFh
        fninit
        fnstsw  [fpu_sw]
        cmp     word [fpu_sw], 0FFFFh
        jne     .has_fpu
        xor     al, al              ; 0 = no FPU
        ret
.has_fpu:
        ; Map cpu_type → fpu_type: 0→1(8087) 1→2(287) 2→3(387) 3+→4(built-in)
        mov     ax, [cpu_type]
        inc     ax
        cmp     ax, 4
        jle     .ok
        mov     ax, 4
.ok:    ret

; ============================================================
; get_cpuid_info: vendor string, family/model/stepping, TSC flag
; Only call when cpu_type == 4 (CPUID available).
; ============================================================
get_cpuid_info:
        push    bx
        push    cx
        push    dx
        push    di

        ; CPUID EAX=0: vendor string in EBX:EDX:ECX
        xor     eax, eax
        cpuid
        mov     di, cpu_vendor
        mov     [di],   ebx
        mov     [di+4], edx
        mov     [di+8], ecx
        mov     byte [di+12], 0

        ; CPUID EAX=1: family/model/stepping; EDX = feature flags
        mov     eax, 1
        cpuid
        ; AX low byte: [3:0]=stepping [7:4]=model; AH: [3:0]=family
        mov     bl, al
        and     bl, 0Fh
        mov     [cpu_stepping], bl
        shr     al, 4
        mov     [cpu_model_num], al
        mov     bl, ah
        and     bl, 0Fh
        mov     [cpu_family], bl
        ; DX bit 4 = TSC; bit 0 = FPU (confirm built-in)
        xor     al, al
        test    dx, 0010h
        jz      .no_tsc
        mov     al, 1
.no_tsc:
        mov     [has_tsc], al
        test    dx, 0001h
        jz      .done
        mov     byte [fpu_type], 4
.done:
        pop     di
        pop     dx
        pop     cx
        pop     bx
        ret

; ============================================================
; get_bios_info: BIOS date (F000:FFF5h, 8 bytes "MM/DD/YY")
; and machine-type byte (F000:FFFEh).
; ============================================================
get_bios_info:
        push    ax
        push    cx
        push    si
        push    di
        push    es

        mov     ax, 0F000h
        mov     es, ax              ; ES = BIOS segment

        mov     si, 0FFF5h
        mov     di, bios_date
        mov     cx, 8
.copy:  mov     al, [es:si]
        inc     si
        mov     [di], al
        inc     di
        loop    .copy
        mov     byte [di], 0

        mov     al, [es:0FFFEh]
        mov     [machine_type], al

        pop     es
        pop     di
        pop     si
        pop     cx
        pop     ax
        ret

; ============================================================
; calc_mb: fills [free_mb] and [total_mb]
; Input: AX=spc, BX=free_cl, CX=bps, DX=total_cl
;
; Old formula (spc*bps→si, then mul si) breaks when spc*bps>65535
; (FAT32 with ≥64 sectors/cluster: 128×512=65536 overflows AX).
;
; Fix: spc_scaled = spc × (bps>>9)  keeps product ≤1024.
; Then mb = (clusters × spc_scaled) >> 11.
; The 32-bit shift uses BX for the high word to avoid the
; CL-clobber that would occur if we stored it in CX.
; ============================================================
calc_mb:
        push    bx
        push    cx
        push    si
        push    bp

        mov     bp, dx          ; BP = total_cl (save before MUL trashes DX)

        ; spc_scaled = spc × (bps>>9): 512→1, 1024→2, 2048→4, 4096→8
        ; max: 128 × 8 = 1024 — never overflows AX
        mov     cl, 9
        shr     cx, cl          ; CX = bps >> 9
        mul     cx              ; AX = spc_scaled, DX = 0
        mov     si, ax

        ; free_mb = (free_cl × spc_scaled) >> 11
        mov     ax, bx          ; AX = free_cl
        mul     si              ; DX:AX = 32-bit product
        mov     bx, dx          ; BX = high word (not CX — avoids CL clobber)
        mov     cl, 11
        shr     ax, cl          ; low contribution
        mov     cl, 5
        shl     bx, cl          ; high word × 32
        add     ax, bx
        mov     [free_mb], ax

        ; total_mb = (total_cl × spc_scaled) >> 11
        mov     ax, bp
        mul     si
        mov     bx, dx
        mov     cl, 11
        shr     ax, cl
        mov     cl, 5
        shl     bx, cl
        add     ax, bx
        mov     [total_mb], ax

        pop     bp
        pop     si
        pop     cx
        pop     bx
        ret

; ============================================================
; print_str / putchar / print_crlf / print8 / print16
; ============================================================
print_str:
        push    ax
        push    dx
.lp:    lodsb
        test    al, al
        jz      .done
        mov     dl, al
        mov     ah, 02h
        int     21h
        jmp     .lp
.done:  pop dx
        pop ax
        ret

putchar:
        push    ax
        mov     ah, 02h
        int     21h
        pop     ax
        ret

print_crlf:
        push    dx
        mov     dl, 13
        call    putchar
        mov     dl, 10
        call    putchar
        pop     dx
        ret

print8:
        push    ax
        push    bx
        push    cx
        push    si
        xor     ah, ah
        mov     byte [dec_buf+5], 0
        mov     cx, dec_buf+5
        test    al, al
        jnz     .x
        dec     cx
        mov     si, cx
        mov     byte [si], '0'
        jmp     .p
.x:     test al, al
        jz   .p
        mov  bl, 10
        div  bl
        dec  cx
        mov  si, cx
        mov  [si], ah
        add  byte [si], '0'
        xor  ah, ah
        jmp  .x
.p:     mov si, cx
        call print_str
        pop si
        pop cx
        pop bx
        pop ax
        ret

print16:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        mov     byte [dec_buf+5], 0
        mov     cx, dec_buf+5
        test    ax, ax
        jnz     .x
        dec     cx
        mov     si, cx
        mov     byte [si], '0'
        jmp     .p
.x:     test ax, ax
        jz   .p
        xor  dx, dx
        mov  bx, 10
        div  bx
        dec  cx
        mov  si, cx
        mov  [si], dl
        add  byte [si], '0'
        jmp  .x
.p:     mov si, cx
        call print_str
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ============================================================
; Data
; ============================================================

dos_major       db 0
dos_minor       db 0
os_ptr          dw 0
cpu_type        dw 0
fpu_type        db 0            ; 0=none 1=8087 2=80287 3=80387 4=built-in
fpu_sw          dw 0            ; scratch for detect_fpu
cpu_vendor      db 0,0,0,0,0,0,0,0,0,0,0,0,0  ; 12-char CPUID vendor + null
cpu_family      db 0
cpu_model_num   db 0
cpu_stepping    db 0
has_tsc         db 0
bios_date       db 0,0,0,0,0,0,0,0,0           ; 8-char BIOS date + null
machine_type    db 0
bios_vendor     times 16 db 0                   ; BIOS vendor string (up to 15 chars + null)
drv_ltr         db 'C'
free_mb         dw 0
total_mb        dw 0
ram_total_kb    dw 0
ram_free_kb     dw 0
dec_buf         db 0,0,0,0,0,0
flag_color      db 1            ; /C off sets to 0
flag_infoonly   db 0            ; /I sets to 1
flag_help       db 0            ; /? sets to 1

; Line pointers for print_logo_line
ld              dw 0
lo              dw 0
ls              dw 0

; Extended disk space buffer (INT 21h AX=7303h), 44 bytes
dfs_buf         times 44 db 0

; Volume label search
srch_path       db 'C:\*.*', 0
label_dta       times 43 db 0
label_buf       times 12 db 0

str_help        db 'DOSFETCH - DOS System Information Fetch', 13, 10
                db 13, 10
                db 'Usage: DOSFETCH [options]', 13, 10
                db 13, 10
                db '  /?       Show this help', 13, 10
                db '  /I       Info only, no ASCII art', 13, 10
                db '  /C on    Enable colors (default)', 13, 10
                db '  /C off   Disable colors', 13, 10
                db 0

; OS name strings
str_msdos       db 'MS-DOS',  0
str_freedos     db 'FreeDOS', 0
str_pcdos       db 'PC-DOS',  0
str_drdos       db 'DR-DOS',  0
str_ptsdos      db 'PTS-DOS', 0

; CPU name table (0-4)
cpu_tbl         dw str_8086, str_286, str_386p, str_486, str_pent
str_8086        db '8086/8088', 0
str_286         db '286', 0
str_386p        db '386', 0
str_486         db '486', 0
str_pent        db 'Pentium+', 0

; FPU name table (0-4)
fpu_tbl         dw str_fpu0, str_fpu1, str_fpu2, str_fpu3, str_fpu4
str_fpu0        db 'None', 0
str_fpu1        db '8087', 0
str_fpu2        db '80287', 0
str_fpu3        db '80387', 0
str_fpu4        db 'Built-in', 0

; Info labels
lbl_os          db '  OS  : ', 0
lbl_cpu         db '  CPU : ', 0
lbl_fpu         db '  FPU : ', 0
lbl_model       db '  Mod : ', 0
lbl_disk        db '  Disk: ', 0
lbl_ram         db '  RAM : ', 0
lbl_bios        db '  BIOS: ', 0

; CPUID / model display helpers
str_f_sep       db ' F', 0
str_tsc_yes     db ' TSC', 0
str_na          db 'N/A', 0

; BIOS vendor pattern table: { length, ascii_string } pairs, 0-terminated.
; More-specific entries first (AMIBIOS before AMI).
bios_pat_tbl:
        db 7, 'SeaBIOS'
        db 7, 'Phoenix'
        db 7, 'AMIBIOS'
        db 5, 'Award'
        db 3, 'AMI'
        db 5, 'Bochs'
        db 4, 'QEMU'
        db 0

str_bios_unk    db 'Unknown', 0

; Format strings
str_mb_of       db 'MB / ', 0
str_mb          db 'MB', 0
str_kb_of       db 'KB / ', 0
str_kb          db 'KB', 0
str_lp          db ' (', 0
str_comma       db ', ', 0

; ============================================================
; Logo — each line split into D / O / S segments.
; Single quotes encoded as 27h.
; D segment includes trailing gap before O.
; O segment includes trailing gap before S.
; ============================================================

l1d db '88888888ba,     ', 0
l1o db ',ad8888ba,    ', 0
l1s db 'ad88888ba  ', 0

l2d db '88      `"8b   ', 0
l2o db 'd8"', 27h, '    `"8b  ', 0
l2s db 'd8"     "8b ', 0

l3d db '88        `8b ', 0
l3o db 'd8', 27h, '        `8b ', 0
l3s db 'Y8,         ', 0

l4d db '88         88 ', 0
l4o db '88          88 ', 0
l4s db '`Y8aaaaa,   ', 0

l5d db '88         88 ', 0
l5o db '88          88   ', 0
l5s db '`"""""8b, ', 0

l6d db '88         8P ', 0
l6o db 'Y8,        ,8P         ', 0
l6s db '`8b ', 0

l7d db '88      .a8P   ', 0
l7o db 'Y8a.    .a8P  ', 0
l7s db 'Y8a     a8P ', 0

l8d db '88888888Y"', 27h, '     ', 0
l8o db '`"Y8888Y"', 27h, '    ', 0
l8s db '"Y88888P"  ', 0          ; 2 extra spaces — l8 total is 39 vs 41 for other lines
