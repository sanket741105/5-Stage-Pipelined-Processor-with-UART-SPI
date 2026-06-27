module test_interrupts;

    reg clk1, clk2;
    reg rst;
    integer k;

    wire uart_tx;
    wire uart_rx;
    wire spi_sclk;
    wire spi_mosi;
    wire spi_miso;
    wire spi_ss;

    // Instantiate MIPS processor
    pipe_MIPS32 mips (
        .clk1(clk1),
        .clk2(clk2),
        .rst(rst),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_ss(spi_ss)
    );

    // Loopback connections
    assign uart_rx = uart_tx;
    assign spi_miso = spi_mosi;

    // Generate Two-Phase Clock
    initial begin
        clk1 = 0; clk2 = 0;
        repeat (250) begin
            #5 clk1 = 1; #5 clk1 = 0;
            #5 clk2 = 1; #5 clk2 = 0;
        end
    end

    // Load Program and Run
    initial begin
        // Reset system
        rst = 1;
        #15;
        rst = 0;

        // Initialize registers
        for (k = 0; k < 32; k = k + 1) begin
            mips.Reg[k] = 0;
        end

        // Clear memory
        for (k = 0; k < 1024; k = k + 1) begin
            mips.Mem[k] = 32'h00000000; // Initialize with NOPs (ADD R0, R0, R0)
        end

        // Main Program (starts at 0)
        mips.Mem[0] = 32'h280203fc;      // PC 0: ADDI R2, R0, 1020 (R2 = UART_DATA)
        mips.Mem[1] = 32'h28030041;      // PC 1: ADDI R3, R0, 65 ('A')
        mips.Mem[2] = 32'h00000000;      // PC 2: NOP
        mips.Mem[3] = 32'h24430000;      // PC 3: SW R3, 0(R2) (Write 'A' to UART_DATA)
        mips.Mem[4] = 32'h00000000;      // PC 4: NOP
        mips.Mem[5] = 32'h00000000;      // PC 5: NOP
        mips.Mem[6] = 32'h3820ffff;      // PC 6: BEQZ R1, -1 (Loop at PC 6 while R1 == 0)

        mips.Mem[7] = 32'h280a03fe;      // PC 7: ADDI R10, R0, 1022 (R10 = SPI_DATA)
        mips.Mem[8] = 32'h280b00aa;      // PC 8: ADDI R11, R0, 170 (R11 = 0xAA)
        mips.Mem[9] = 32'h00000000;      // PC 9: NOP
        mips.Mem[10] = 32'h254b0000;     // PC 10: SW R11, 0(R10) (Write 0xAA to SPI_DATA)
        mips.Mem[11] = 32'h28010000;     // PC 11: ADDI R1, R0, 0 (R1 = 0)
        mips.Mem[12] = 32'h00000000;     // PC 12: NOP
        mips.Mem[13] = 32'h00000000;     // PC 13: NOP
        mips.Mem[14] = 32'h3820ffff;     // PC 14: BEQZ R1, -1 (Loop at PC 14 while R1 == 0)
        mips.Mem[15] = 32'h00000000;     // PC 15: NOP
        mips.Mem[16] = 32'h00000000;     // PC 16: NOP
        mips.Mem[17] = 32'hfc000000;     // PC 17: HLT

        // Interrupt Service Routine (starts at 500)
        mips.Mem[500] = 32'h280c03fa;    // PC 500: ADDI R12, R0, 1018 (R12 = ICAUSE)
        mips.Mem[501] = 32'h00000000;    // PC 501: NOP
        mips.Mem[502] = 32'h00000000;    // PC 502: NOP
        mips.Mem[503] = 32'h218d0000;    // PC 503: LW R13, 0(R12) (R13 = ICAUSE)
        mips.Mem[504] = 32'h280e0002;    // PC 504: ADDI R14, R0, 2 (R14 = 2)
        mips.Mem[505] = 32'h00000000;    // PC 505: NOP
        mips.Mem[506] = 32'h00000000;    // PC 506: NOP
        mips.Mem[507] = 32'h05ae7800;    // PC 507: SUB R15, R13, R14 (R15 = ICAUSE - 2)
        mips.Mem[508] = 32'h00000000;    // PC 508: NOP
        mips.Mem[509] = 32'h00000000;    // PC 509: NOP
        mips.Mem[510] = 32'h39e00006;    // PC 510: BEQZ R15, 6 (If SPI interrupt, branch to PC 517)

        // UART Interrupt Handler
        mips.Mem[511] = 32'h281003fc;    // PC 511: ADDI R16, R0, 1020 (R16 = UART_DATA)
        mips.Mem[512] = 32'h00000000;    // PC 512: NOP
        mips.Mem[513] = 32'h00000000;    // PC 513: NOP
        mips.Mem[514] = 32'h22110000;    // PC 514: LW R17, 0(R16) (Read character, clears interrupt)
        mips.Mem[515] = 32'h28010001;    // PC 515: ADDI R1, R0, 1 (R1 = 1, breaks UART loop)
        mips.Mem[516] = 32'h38000005;    // PC 516: BEQZ R0, 5 (Branch to PC 522 - Exit ISR)

        // SPI Interrupt Handler
        mips.Mem[517] = 32'h281203fe;    // PC 517: ADDI R18, R0, 1022 (R18 = SPI_DATA)
        mips.Mem[518] = 32'h00000000;    // PC 518: NOP
        mips.Mem[519] = 32'h00000000;    // PC 519: NOP
        mips.Mem[520] = 32'h22530000;    // PC 520: LW R19, 0(R18) (Read SPI RX data)
        mips.Mem[521] = 32'h28010002;    // PC 521: ADDI R1, R0, 2 (R1 = 2, breaks SPI loop)

        // Exit ISR
        mips.Mem[522] = 32'h00000000;    // PC 522: NOP
        mips.Mem[523] = 32'h00000000;    // PC 523: NOP
        mips.Mem[524] = 32'h3c000000;    // PC 524: ERET (Return from Interrupt)

        $display("====================== STARTING SIMULATION ======================");
        
        // Wait until halted
        wait(mips.HALTED == 1);
        #50;

        $display("\n===================== SIMULATION RESULT =====================");
        $display("R1   (Interrupt status indicator) : %d (Expected: 2)", mips.Reg[1]);
        $display("R17  (Received UART character)    : %d ('%c') (Expected: 65 ('A'))", mips.Reg[17], mips.Reg[17]);
        $display("R19  (Received SPI loopback byte) : 0x%h (Expected: 0xaa)", mips.Reg[19]);
        $display("=============================================================");
        $finish;
    end

    // Monitor trace
    always @(posedge clk1) begin
        if (!rst) begin
            $display("[Time %0t] [CPU] PC = %0d, IF_ID_IR = 0x%h, IE = %b, EPC = %d, ICAUSE = %d, Reg[1] = %d, R13=%d, R14=%d, R15=%d", 
                     $time, mips.PC, mips.IF_ID_IR, mips.IE, mips.EPC, mips.ICAUSE, mips.Reg[1], mips.Reg[13], mips.Reg[14], mips.Reg[15]);
            if (mips.EX_MEM_type == 3'b011 && mips.TAKEN_BRANCH == 0 && mips.EX_MEM_ALUOut == 32'd1020) begin
                $display("[Time %0t] [CPU] Writing character '%c' (0x%h) to UART", $time, mips.EX_MEM_B[7:0], mips.EX_MEM_B[7:0]);
            end
            if (mips.EX_MEM_type == 3'b011 && mips.TAKEN_BRANCH == 0 && mips.EX_MEM_ALUOut == 32'd1022) begin
                $display("[Time %0t] [CPU] Starting SPI transmission with data 0x%h", $time, mips.EX_MEM_B[7:0]);
            end
            if (mips.trigger_interrupt) begin
                $display("[Time %0t] [CPU] *** INTERRUPT TRIGGERED *** Cause = %0d. PC = %0d. Saving PC to EPC and jumping to vector 500", $time, mips.uart_intr ? 1 : 2, mips.PC);
            end
            if (mips.EX_MEM_type == 3'b110 && mips.EX_MEM_IR[31:26] == 6'b001111) begin
                $display("[Time %0t] [CPU] ERET executed. Returning to EPC = %0d and re-enabling interrupts", $time, mips.EPC);
            end
        end
    end

endmodule
