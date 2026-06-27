module pipe_MIPS32 (
    input clk1, clk2,
    input rst,
    input uart_rx,
    output uart_tx,
    output spi_sclk,
    output spi_mosi,
    input spi_miso,
    output spi_ss
);

    reg [31:0] PC, IF_ID_IR, IF_ID_NPC;
    reg [31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm;
    reg [2:0]  ID_EX_type, EX_MEM_type, MEM_WB_type;
    reg [31:0] EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
    reg        EX_MEM_cond;
    reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;

    reg [31:0] Reg [0:31];          //Register Bank (32 X 32)
    reg [31:0] Mem [0:1023];        //1024 X 32 Memory

    // Interrupt Control Registers
    reg IE;
    reg [31:0] EPC;
    reg [31:0] ICAUSE;

    reg [7:0] uart_tx_data;
    reg uart_tx_start;
    wire [7:0] uart_rx_data;
    wire uart_rx_ready;
    reg uart_rx_read_en;
    wire uart_tx_busy;
    wire uart_intr;

    reg [7:0] spi_tx_data;
    reg spi_start;
    wire [7:0] spi_rx_data;
    wire spi_busy;
    wire spi_done;
    wire spi_intr;
    reg spi_rx_read_en;

    parameter ADD=6'b000000, SUB=6'b000001, AND=6'b000010, OR=6'b000011, SLT=6'b000100;
    parameter MUL=6'b000101, HLT=6'b111111, LW=6'b001000, SW=6'b001001, ADDI=6'b001010;
    parameter SUBI=6'b001011, SLTI=6'b001100, BNEQZ=6'b001101, BEQZ=6'b001110;
    parameter ERET=6'b001111, EI=6'b010000, DI=6'b010001;

    parameter RR_ALU=3'b000, RM_ALU=3'b001, LOAD=3'b010, STORE=3'b011;
    parameter BRANCH=3'b100, HALT=3'b101, SYSTEM=3'b110;

    reg HALTED;                    
        //Set after HLT instruction is completed (WB Stage)
    reg TAKEN_BRANCH;
        // Required to disable instructions after branch

    wire is_branch_taken = (((EX_MEM_IR[31:26] == BEQZ)&&(EX_MEM_cond==1)) || ((EX_MEM_IR[31:26] == BNEQZ)&& (EX_MEM_cond ==0)));
    wire is_eret = (EX_MEM_IR[31:26] == ERET);
    wire trigger_interrupt = IE && (uart_intr || spi_intr) && !is_branch_taken && !is_eret;

    always @(posedge clk1 or posedge rst)          //***IF Stage***
        if (rst) begin
            PC           <= #2 0;
            IF_ID_IR     <= #2 32'h00000000; // NOP
            IF_ID_NPC    <= #2 0;
            TAKEN_BRANCH <= #2 0;
            IE           <= #2 1'b1;
            EPC          <= #2 0;
            ICAUSE       <= #2 0;
            HALTED       <= #2 1'b0;
        end else if (HALTED == 0) begin
            // Process writes to IE/EPC from the instruction that just finished MEM stage
            if (EX_MEM_type == STORE && TAKEN_BRANCH == 0) begin
                if (EX_MEM_ALUOut == 32'd1016)
                    IE <= #2 EX_MEM_B[0];
                else if (EX_MEM_ALUOut == 32'd1017)
                    EPC <= #2 EX_MEM_B;
            end else if (EX_MEM_type == SYSTEM) begin
                if (EX_MEM_IR[31:26] == EI)
                    IE <= #2 1'b1;
                else if (EX_MEM_IR[31:26] == DI)
                    IE <= #2 1'b0;
                else if (EX_MEM_IR[31:26] == ERET)
                    IE <= #2 1'b1;
            end

            // Handle interrupts or normal execution (IF stage)
            if (trigger_interrupt) begin
                EPC          <= #2 PC;
                ICAUSE       <= #2 uart_intr ? 32'd1 : 32'd2;
                IE           <= #2 1'b0;
                PC           <= #2 32'd500;
                IF_ID_IR     <= #2 32'h00000000; // NOP
                IF_ID_NPC    <= #2 32'd500;
                TAKEN_BRANCH <= #2 1'b0;
            end else if (is_branch_taken || is_eret) begin
                IF_ID_IR     <= #2 Mem[EX_MEM_ALUOut];
                TAKEN_BRANCH <= #2 1'b1;
                IF_ID_NPC    <= #2 EX_MEM_ALUOut+1;
                PC           <= #2 EX_MEM_ALUOut+1;
            end else begin
                IF_ID_IR     <= #2 Mem[PC];
                IF_ID_NPC    <= #2 PC+1;
                PC           <= #2 PC+1;
                TAKEN_BRANCH <= #2 1'b0;
            end
        end

    always @(posedge clk2)          //ID Stage
        if (HALTED==0)
        begin
            if(IF_ID_IR[25:21]==5'b00000) ID_EX_A <= #2 0;  // rs
            else ID_EX_A <= #2 Reg[IF_ID_IR[25:21]];   

            if(IF_ID_IR[20:16]==5'b00000) ID_EX_B <= #2 0;  // rt
            else ID_EX_B <= #2 Reg[IF_ID_IR[20:16]];   

            ID_EX_NPC <= #2 IF_ID_NPC;
            ID_EX_IR  <= #2 IF_ID_IR;
            ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, {IF_ID_IR[15:0]}};

            case( IF_ID_IR[31:26])
              ADD,SUB,MUL,AND,OR,SLT: ID_EX_type <= #2 RR_ALU;
              ADDI,SUBI,SLTI:         ID_EX_type <= #2 RM_ALU;
              LW:                     ID_EX_type <= #2 LOAD;
              SW:                     ID_EX_type <= #2 STORE;
              BNEQZ,BEQZ:             ID_EX_type <= #2 BRANCH;
              ERET,EI,DI:             ID_EX_type <= #2 SYSTEM;
              HLT:                    ID_EX_type <= #2 HALT;
              default:                ID_EX_type <= #2 HALT;     //Inavlid Operation
            endcase
        end
 
    always @(posedge clk1)              // EX Stage
        if(HALTED==0)
        begin
            EX_MEM_cond <= #2 0;
            if (trigger_interrupt) begin
                EX_MEM_type   <= #2 RR_ALU;
                EX_MEM_IR     <= #2 32'h00000000; // NOP
                EX_MEM_ALUOut <= #2 0;
            end else begin
                EX_MEM_type <= #2 ID_EX_type;
                EX_MEM_IR   <= #2 ID_EX_IR;

                case (ID_EX_type)
                  RR_ALU: begin
                            case(ID_EX_IR[31:26])
                              ADD:   EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
                              SUB:   EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
                              MUL:   EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
                              OR :   EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
                              AND:   EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
                              SLT:   EX_MEM_ALUOut <= #2 ID_EX_A < ID_EX_B;
                              default:   EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                            endcase
                           end   

                  RM_ALU:  begin
                             case(ID_EX_IR[31:26])
                               ADDI:   EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
                               SUBI:   EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_Imm;
                               SLTI:   EX_MEM_ALUOut <= #2 ID_EX_A < ID_EX_Imm;
                               default:   EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                             endcase
                           end

                  LOAD, STORE:  begin
                                 EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
                                 EX_MEM_B      <= #2 ID_EX_B;
                                end

                   BRANCH: begin
                            EX_MEM_ALUOut <= #2 ID_EX_NPC + ID_EX_Imm;               
                            EX_MEM_cond   <= #2 (ID_EX_A==0);
                           end

                   SYSTEM: begin
                            if (ID_EX_IR[31:26] == ERET) begin
                                EX_MEM_ALUOut <= #2 EPC;
                            end
                           end
                endcase
            end
        end   

    always @(posedge clk2)                        //MEM Stage
        if(HALTED==0)
        begin
          MEM_WB_type <= #2 EX_MEM_type;
          MEM_WB_IR   <= #2 EX_MEM_IR;

        case(EX_MEM_type)
            RR_ALU, RM_ALU:
                     MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;
            
            LOAD:    begin
                       if (EX_MEM_ALUOut == 32'd1016)
                         MEM_WB_LMD <= #2 {31'b0, IE};
                       else if (EX_MEM_ALUOut == 32'd1017)
                         MEM_WB_LMD <= #2 EPC;
                       else if (EX_MEM_ALUOut == 32'd1018)
                         MEM_WB_LMD <= #2 ICAUSE;
                       else if (EX_MEM_ALUOut == 32'd1020) begin
                         MEM_WB_LMD <= #2 {24'b0, uart_rx_data};
                         uart_rx_read_en <= #2 1'b1;
                       end
                       else if (EX_MEM_ALUOut == 32'd1021)
                         MEM_WB_LMD <= #2 {30'b0, uart_tx_busy, uart_rx_ready};
                       else if (EX_MEM_ALUOut == 32'd1022) begin
                         MEM_WB_LMD <= #2 {24'b0, spi_rx_data};
                         spi_rx_read_en <= #2 1'b1;
                       end
                       else if (EX_MEM_ALUOut == 32'd1023)
                         MEM_WB_LMD <= #2 {30'b0, spi_busy, spi_done};
                       else
                         MEM_WB_LMD <= #2 Mem[EX_MEM_ALUOut]; 
                     end

            STORE:  if(TAKEN_BRANCH == 0) begin
                       if (EX_MEM_ALUOut == 32'd1016)
                         // Handled in clk1 block for IE register
                         ;
                       else if (EX_MEM_ALUOut == 32'd1017)
                         // Handled in clk1 block for EPC register
                         ;
                       else if (EX_MEM_ALUOut == 32'd1020) begin
                         uart_tx_data <= #2 EX_MEM_B[7:0];
                         uart_tx_start <= #2 1'b1;
                       end
                       else if (EX_MEM_ALUOut == 32'd1022) begin
                         spi_tx_data <= #2 EX_MEM_B[7:0];
                         spi_start <= #2 1'b1;
                       end
                       else
                         Mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;
                     end

            SYSTEM: begin
                      MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;
                    end
        endcase           
        end  

    always @(posedge clk1)              // WB Stage
        begin
        if(TAKEN_BRANCH == 0)           // Disable Write if branch taken 
           case(MEM_WB_type)
            RR_ALU:   Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut;
            RM_ALU:   Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut;
           
           LOAD:     Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;
           HALT:     HALTED <= #2 1'b1;
           endcase
        end
    always @(posedge clk1 or posedge rst) begin // Clear start signals
        if (rst) begin
            uart_rx_read_en <= 0;
            uart_tx_start <= 0;
            spi_start <= 0;
            spi_rx_read_en <= 0;
        end else begin
            uart_rx_read_en <= #2 1'b0;
            uart_tx_start <= #2 1'b0;
            spi_start <= #2 1'b0;
            spi_rx_read_en <= #2 1'b0;
        end
    end

    assign uart_intr = uart_rx_ready;

    uart_tx #(.CLKS_PER_BIT(8)) utx (
        .clk(clk1),
        .rst(rst),
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx(uart_tx),
        .tx_busy(uart_tx_busy)
    );

    uart_rx #(.CLKS_PER_BIT(8)) urx (
        .clk(clk1),
        .rst(rst),
        .rx(uart_rx),
        .rx_data(uart_rx_data),
        .rx_ready(uart_rx_ready),
        .rx_read_en(uart_rx_read_en)
    );

    spi_master sm (
        .clk(clk1),
        .rst(rst),
        .tx_data(spi_tx_data),
        .start(spi_start),
        .intr_clear(spi_rx_read_en),
        .rx_data(spi_rx_data),
        .busy(spi_busy),
        .done(spi_done),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .ss(spi_ss),
        .intr(spi_intr)
    );

endmodule