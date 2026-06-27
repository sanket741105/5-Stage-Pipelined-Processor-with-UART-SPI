module spi_master (
    input clk,
    input rst,
    input [7:0] tx_data,
    input start,
    input intr_clear,
    output reg [7:0] rx_data,
    output reg busy,
    output reg done,
    output reg sclk,
    output reg mosi,
    input miso,
    output reg ss,
    output reg intr
);
    reg [2:0] state;
    reg [3:0] clk_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg_tx;
    reg [7:0] shift_reg_rx;

    localparam IDLE = 3'd0;
    localparam TRAMSMIT = 3'd1;
    localparam DONE_STATE = 3'd2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            sclk <= 0;
            mosi <= 0;
            ss <= 1;
            rx_data <= 0;
            shift_reg_tx <= 0;
            shift_reg_rx <= 0;
            clk_cnt <= 0;
            bit_cnt <= 0;
            intr <= 0;
        end else begin
            if (intr_clear) begin
                intr <= 0;
            end
            case (state)
                IDLE: begin
                    sclk <= 0;
                    ss <= 1;
                    done <= 0;
                    if (start) begin
                        busy <= 1;
                        ss <= 0;
                        shift_reg_tx <= tx_data;
                        clk_cnt <= 0;
                        bit_cnt <= 0;
                        intr <= 0;
                        state <= TRAMSMIT;
                    end
                end
                TRAMSMIT: begin
                    // Divide system clock by 4 to generate SPI clock
                    if (clk_cnt == 0) begin
                        sclk <= 0;
                        mosi <= shift_reg_tx[7 - bit_cnt];
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt == 1) begin
                        sclk <= 1; // Rising edge, shift-in MISO
                        shift_reg_rx[7 - bit_cnt] <= miso;
                        clk_cnt <= clk_cnt + 1;
                    end else if (clk_cnt == 2) begin
                        sclk <= 1;
                        clk_cnt <= clk_cnt + 1;
                    end else begin // clk_cnt == 3
                        sclk <= 0;
                        clk_cnt <= 0;
                        if (bit_cnt < 7) begin
                            bit_cnt <= bit_cnt + 1;
                        end else begin
                            state <= DONE_STATE;
                        end
                    end
                end
                DONE_STATE: begin
                    sclk <= 0;
                    ss <= 1;
                    busy <= 0;
                    done <= 1;
                    rx_data <= shift_reg_rx;
                    intr <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
