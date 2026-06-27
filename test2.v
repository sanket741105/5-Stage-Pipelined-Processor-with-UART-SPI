module test2_mips32;

reg clk1 , clk2;
integer k;

pipe_MIPS32 mips2 (
    .clk1(clk1),
    .clk2(clk2),
    .rst(1'b0),
    .uart_rx(1'b1),
    .uart_tx(),
    .spi_sclk(),
    .spi_mosi(),
    .spi_miso(1'b1),
    .spi_ss()
);

initial begin
   clk1=0; clk2=0;
    repeat(50)
   begin
    #5 clk1=1; #5 clk1=0;
    #5 clk2=1; #5 clk2=0;
   end
end

initial
    begin
        for(k=0; k<31; k=k+1)
          mips2.Reg[k]=k;

        mips2.Mem[0] = 32'h28010078;      //ADDI R1,R0,120
        mips2.Mem[1] = 32'h0c631800;      //OR R3,R3,R3 --- DUMMY INSTR.
        mips2.Mem[2] = 32'h20220000;      //LW R2,0(R1)
        mips2.Mem[3] = 32'h0c631800;      //OR R3,R3,R3 --- DUMMY INSTR.
        mips2.Mem[4] = 32'h2842002d;      //ADDI R2,R2,45
        mips2.Mem[5] = 32'h0c631800;      //OR R3,R3,R3 --- DUMMY INSTR.
        mips2.Mem[6] = 32'h24220001;      //SW R2,1(R1)
        mips2.Mem[7] = 32'hfc000000;      //HLT

        mips2.Mem[120] = 85;

        mips2.HALTED=0;
        mips2.PC=0;
        mips2.TAKEN_BRANCH=0;

        #500 $display("Mem[120] : %4d \nMem[121] : %4d", mips2.Mem[120], mips2.Mem[121]);
    end
     initial
    begin
        $dumpfile ("mips2.vcd");
        $dumpvars (0,test2_mips32);
        #600 $finish;
    end


endmodule