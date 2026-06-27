# 5-Stage-Pipeline-Processor with UART & SPI

MIPS-like 5-stage pipeline processor in Verilog. Supports interrupts and memory-mapped IO.

## Setup
Compile and run the interrupt testbench:
```bash
iverilog -o sim test_interrupts.v processor.v uart.v spi.v
vvp sim
```

Other CPU tests:
```bash
iverilog -o t1 test1.v processor.v uart.v spi.v && vvp t1
iverilog -o t2 test2.v processor.v uart.v spi.v && vvp t2
```

## Assembly Programming & NOPs (Important!)
Since there is no data forwarding in this CPU pipeline, you MUST insert NOPs to handle hazards.
Example (write then read):
```assembly
ADDI R3, R0, 65
NOP
SW R3, 0(R2)
```
If you don't add NOPs, instructions will read stale register data.

## Memory Mapped IO Addresses
- 1016: Interrupt Enable (IE)
- 1017: Exception Program Counter (EPC)
- 1018: Interrupt Cause (ICAUSE) - 1 for UART, 2 for SPI
- 1020: UART Data (read to clear interrupt, write to transmit)
- 1021: UART Status
- 1022: SPI Data (read to clear interrupt, write to transmit)
- 1023: SPI Status

## Interrupts
Interrupts jump to address 500. Read ICAUSE to see what triggered it, handle the peripheral, and exit with ERET.
