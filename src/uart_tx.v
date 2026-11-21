`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// UART transmitter
//////////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter integer CLKS_PER_BIT = 10416
)(
    input  wire       clk,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_busy,
    output reg        tx
);

    reg [3:0] bit_index;
    reg [15:0] clock_count;
    reg [7:0] shift_data;
    reg [1:0] state;

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                tx <= 1'b1;
                tx_busy <= 1'b0;
                clock_count <= 0;
                bit_index <= 0;
                if (tx_start) begin
                    shift_data <= tx_data;
                    tx_busy <= 1'b1;
                    state <= START;
                end
            end

            START: begin
                tx <= 1'b0;
                if (clock_count < CLKS_PER_BIT - 1)
                    clock_count <= clock_count + 1'b1;
                else begin
                    clock_count <= 0;
                    state <= DATA;
                end
            end

            DATA: begin
                tx <= shift_data[bit_index];
                if (clock_count < CLKS_PER_BIT - 1)
                    clock_count <= clock_count + 1'b1;
                else begin
                    clock_count <= 0;
                    if (bit_index < 7)
                        bit_index <= bit_index + 1'b1;
                    else begin
                        bit_index <= 0;
                        state <= STOP;
                    end
                end
            end

            STOP: begin
                tx <= 1'b1;
                if (clock_count < CLKS_PER_BIT - 1)
                    clock_count <= clock_count + 1'b1;
                else begin
                    clock_count <= 0;
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end

endmodule
