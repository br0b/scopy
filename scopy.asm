; The page size on most computers is 4kB.
; If we were to write only a part of a page,
; the OS would have to combine the old contents
; of the page with our write.
BUFFER_SIZE equ 4096

SYS_WRITE equ 1
SYS_OPEN  equ 2
SYS_CLOSE equ 3
SYS_EXIT  equ 60

; These values conform to the sys_open specification.
O_WRONLY equ 0o0000001
O_CREAT  equ 0o0000100
O_EXCL   equ 0o0000200
S_IRUSR  equ 0o400
S_IWUSR  equ 0o200
S_IRGRP  equ 0o040
S_IROTH  equ 0o004

SYSCALL_ERROR equ -1

%macro exit_with_code_1_if_rax_is_negative 0

  cmp   rax, 0
  jl    _start.exit_with_code_1

%endmacro

; Clobbers register r11.
%macro set_rdx_to_1_if_rax_is_negative 0

  mov   r11, 1
  cmp   rax, 0
  cmovl rdx, r11

%endmacro

%macro set_flags_and_mode_for_creating_output_file 0

  ; Add appropriate file creation flags to rsi.
  mov   rsi, O_WRONLY
  or    rsi, O_CREAT
  or    rsi, O_EXCL
  
  ; Set rdx to the -rw-r--r-- mode.
  mov   rdx, S_IRUSR
  or    rdx, S_IWUSR
  or    rdx, S_IRGRP
  or    rdx, S_IROTH

%endmacro

section .bss

input_buffer: resb BUFFER_SIZE
output_buffer: resb BUFFER_SIZE

section .text

; When this process is initialized, the stack frame looks like this:
;   * [rsp + 24] - output file name,
;   * [rsp + 16] - input file name,
;   * [rsp]      - number of arguments of this program.
; The registers are used in the following ways:
;   * bx  - k mod 2^64. Meaning of k is defined below,
;   * most significant bit of ebx - a flag.
;     It is set to 1 if k > 0 and 0 if k is 0.
;     From now on, we will refer to this flag as
;     "k's flag".
;   * r8  - number of bytes in the output buffer,
;   * r9  - number of bytes in the input buffer,
;   * r10 - number of bytes read from the input buffer,
;   * r12 - input file descriptor,
;   * r13 - output file descriptor.
global _start
_start:
  ; If number of command line arguments> is not 2,
  ; exit program with exit code 1.
  cmp   byte [rsp], 0x3 
  jne   .exit_with_code_1

  ; Set the input and output file descriptors to -1
  ; to indicate, that the files haven't been yet
  ; successfully opened.
  mov   r12, -1
  mov   r13, r12

  ; Set number of bytes currently stored in the output buffer
  ; to zero.
  xor   r8, r8

  ; Set k to zero, where k is the number of bytes
  ; of the current maximal and nonempty sequence
  ; of bytes not containing a byte, whose value is the ASCII
  ; code of either character 's' or character 'S'.
  ;
  ; This also sets k's flag to zero.
  ; We use this additional flag to be able to differentiate
  ; whether register bx is zero because k is zero or
  ; because 65536 divides k.
  xor   ebx, ebx

; Open file in a read only access mode.
.open_input:
  mov   rax, SYS_OPEN
  mov   rdi, [rsp + 16] ; Load address of input file name to rdi.
  xor   rsi, rsi        ; Set rsi to O_RDONLY flag.
  syscall
  exit_with_code_1_if_rax_is_negative

  ; Update the input file descriptor.
  mov   r12, rax

; Create a file with -rw-r--r-- mode.
.create_output:
  mov   rax, SYS_OPEN
  mov   rdi, [rsp + 24] ; Load address of output file name to rdi.

  set_flags_and_mode_for_creating_output_file

  ; Call creat(output_file, rsi, rdx).
  syscall               
  exit_with_code_1_if_rax_is_negative

  ; Update the output file descriptor.
  mov   r13, rax

; Get next BUFFER_SIZE bytes from the input file and
; read them.
.read_next_buffer:
  ; Call sys_read.
  xor   rax, rax ; Set rax to SYS_READ.
  mov   rdi, r12
  mov   rsi, input_buffer
  mov   rdx, BUFFER_SIZE
  syscall
  exit_with_code_1_if_rax_is_negative
  
  ; Set some of buffered_write_to_file and
  ; buffered_write_k_to_file functions' arguments.
  mov   rdi, r13           ; Output file descriptor.
  mov   rsi, output_buffer ; Output buffer.
  mov   rdx, BUFFER_SIZE   ; Buffer size.

  ; If no bytes have been read, stop reading the file.
  test  rax, rax
  jz    .stop_reading_file

  ; Update the number of bytes in the input buffer.
  mov   r9, rax

  ; Set the number of bytes read from the input buffer to zero.
  xor   r10, r10

.read_next_byte:
  ; If there are no more bytes to read in the input buffer, read file.
  cmp  r9, r10
  je   .read_next_buffer

  ; If the next byte to process is the ASCII code of either 's'
  ; or 'S', then update the output buffer...
  cmp   byte [input_buffer + r10], 's'
  je    .write_to_file
  cmp   byte [input_buffer + r10], 'S'
  je    .write_to_file

  ; ...otherwise increment k, set its flag to 1,
  ; increment the number of bytes read and read next byte.
  add   bx, 1
  or    ebx, 0x80000000
  add   r10, 1
  jmp   .read_next_byte

.write_to_file:
  ; If the k's flag is set to zero, then skip writing k mod 65536.
  bt    ebx, 31
  jnc   .write_s_or_S

.write_k:
  mov   cx, bx
  call  buffered_write_k_to_file
  
  ; Reset k and its flag.
  xor   bx, bx
  and   ebx, 0x7fffffff

.write_s_or_S:
  mov   cl, [input_buffer + r10]
  call  buffered_write_to_file

  add   r10, 1
  jmp   .read_next_byte

; All bytes from the input file have been read.
.stop_reading_file:
  ; If k is 0, jump to final write to file...
  bt    ebx, 31 ; Check k's flag.
  jnc   .final_buffer_write

  ; ...otherwise write k to buffer.
  mov   cx, bx
  call  buffered_write_k_to_file

; If there are any bytes left in the output buffer,
; they have to be written.
.final_buffer_write:
  ; If the output buffer is empty, exit with code 0...
  test  r8, r8
  jz    .exit_with_code_0

  ; Write the remaining bytes from the output buffer
  ; to the output file.
  mov   rdx, r8
  call  write_buffer_to_file

.exit_with_code_0:
  xor   rdx, rdx ; Set exit code to zero.
  jmp   .close_input_file

.exit_with_code_1:
  mov   rdx, 1

; If the input file has been opened, close it.
.close_input_file:
  ; If the input file hasn't been opened,
  ; then the output file also hasn't been opened
  ; and we can exit the program.
  cmp   r12, -1
  je   .exit

  mov   rax, SYS_CLOSE
  mov   rdi, r12
  syscall
  set_rdx_to_1_if_rax_is_negative

; If the output file has been opened, close it.
.close_output_file:
  ; If the output file hasn't been opened,
  ; then we can exit the program.
  cmp   r13, -1
  je   .exit

  mov   rax, SYS_CLOSE
  mov   rdi, r13
  syscall
  set_rdx_to_1_if_rax_is_negative

; Exit program. The exit code is stored in rdx.
.exit:
  mov   rax, SYS_EXIT
  mov   rdi, rdx
  syscall

; Arguments:
;   * rdi - open output file descriptor,
;   * rsi - output buffer,
;   * rdx - buffer size. Has to be at least one byte,
;   * cl  - byte to save to the output file,
;   * r8  - number of bytes in the output buffer.
; Returns void. If a write error occurs, exits with code 1.
; Updates r8 to the new number of bytes in the output buffer.
; Every other register beside r8 and r11 is saved.
buffered_write_to_file:
  ; If there is at least one free byte in the buffer,
  ; then add the byte to the buffer...
  cmp   r8, rdx
  jb    .push_buffer
  
  ; Write buffer to the output file and set the number of bytes in the output
  ; buffer to zero.
  call  write_buffer_to_file
  xor   r8, r8

.push_buffer: 
  mov   [rsi + r8], cl
  add   r8, 1 ; Register r8 is at most equal to the buffer size in rdx.

  ret

; This is a wrapper for sys_write that handles situations,
; when not all of the bytes from the buffer have been written.
; Arguments:
;   * rdi - open output file descriptor,
;   * rsi - beginning of the byte sequence to write,
;   * rdx - length of the byte sequence.
; All registers are saved except r11.
write_buffer_to_file:
  push  rsi
  push  rdx
  push  rcx

.write_buffer:
  mov   rax, SYS_WRITE
  syscall
  exit_with_code_1_if_rax_is_negative

  ; If not all bytes have been written, update sys_write arguments and
  ; try to write the rest.
  cmp   rax, rdx
  je    .return
  add   rsi, rax
  sub   rdx, rax
  jmp   .write_buffer

.return:
  pop   rcx
  pop   rdx
  pop   rsi
  ret

; Write k mod 65536 using little-endian to file using a buffer.
; Arguments:
;   * rdi - open output file descriptor,
;   * rsi - output buffer,
;   * rdx - buffer size. Has to be at least one byte,
;   * cx  - k,
;   * r8  - number of bytes in the output buffer.
; Returns void. If a write error occurs, exits with code 1.
; Updates r8 to the new number of bytes in the output buffer.
; Every other register beside r8 is saved.
buffered_write_k_to_file:
  ; Write low byte of k mod 65536.
  call  buffered_write_to_file

  ; Write high byte of k mod 65536.
  mov   cl, ch
  call  buffered_write_to_file

  ret
