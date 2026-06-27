module uart_tx #(parameter CLKS_PER_BIT = 8) (
    input clk,
    input rst,
    input [7:0] tx_data,
    input tx_start,
    output reg tx,
    output reg tx_busy
);
    reg [2:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] tx_reg;

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx <= 1'b1;
            tx_busy <= 1'b0;
            clk_cnt <= 0;
            bit_idx <= 0;
            tx_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (tx_start) begin
                        tx_reg <= tx_data;
                        tx_busy <= 1'b1;
                        state <= START;
                    end
                end
                START: begin
                    tx <= 1'b0; // Start bit
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        state <= DATA;
                    end
                end
                DATA: begin
                    tx <= tx_reg[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            bit_idx <= 0;
                            state <= STOP;
                        end
                    end
                end
                STOP: begin
                    tx <= 1'b1; // Stop bit
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        tx_busy <= 1'b0;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

module uart_rx #(parameter CLKS_PER_BIT = 8) (
    input clk,
    input rst,
    input rx,
    output reg [7:0] rx_data,
    output reg rx_ready,
    input rx_read_en
);
    reg [2:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] rx_reg;
    reg rx_sync;
    reg rx_d;

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    // Double flip-flop to synchronize input rx signal
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync <= 1'b1;
            rx_d <= 1'b1;
        end else begin
            rx_sync <= rx;
            rx_d <= rx_sync;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            clk_cnt <= 0;
            bit_idx <= 0;
            rx_reg <= 0;
            rx_data <= 0;
            rx_ready <= 1'b0;
        end else begin
            if (rx_read_en) begin
                rx_ready <= 1'b0;
            end

            case (state)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_d == 1'b0) begin // Detect start bit (falling edge)
                        state <= START;
                    end
                end
                START: begin
                    // Sample at the middle of the start bit
                    if (clk_cnt == (CLKS_PER_BIT / 2)) begin
                        if (rx_d == 1'b0) begin
                            clk_cnt <= 0;
                            state <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                DATA: begin
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        rx_reg[bit_idx] <= rx_d;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            bit_idx <= 0;
                            state <= STOP;
                        end
                    end
                end
                STOP: begin
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        if (rx_d == 1'b1) begin // Valid stop bit
                            rx_data <= rx_reg;
                            rx_ready <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
