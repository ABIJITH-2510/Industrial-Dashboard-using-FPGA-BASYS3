`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: i2c_master
//////////////////////////////////////////////////////////////////////////////////

module i2c_master #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer I2C_FREQ_HZ   = 100_000
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       command_valid,
    input  wire [2:0] command,
    input  wire [7:0] tx_data,
    output reg  [7:0] rx_data,
    output reg        busy,
    output reg        done,
    output reg        ack_error,
    output wire       scl,
    inout  wire       sda
);

    localparam [2:0] CMD_START     = 3'd0;
    localparam [2:0] CMD_STOP      = 3'd1;
    localparam [2:0] CMD_WRITE     = 3'd2;
    localparam [2:0] CMD_READ_ACK  = 3'd3;
    localparam [2:0] CMD_READ_NACK = 3'd4;

    localparam integer QUARTER_COUNT = CLOCK_FREQ_HZ / (I2C_FREQ_HZ * 4);

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_START      = 4'd1;
    localparam [3:0] ST_STOP       = 4'd2;
    localparam [3:0] ST_WRITE_BIT  = 4'd3;
    localparam [3:0] ST_WRITE_ACK  = 4'd4;
    localparam [3:0] ST_READ_BIT   = 4'd5;
    localparam [3:0] ST_READ_ACK   = 4'd6;

    reg [3:0]  state;
    reg [2:0]  active_command;
    reg [7:0]  shift_reg;
    reg [2:0]  bit_index;
    reg [1:0]  phase;
    reg [15:0] quarter_counter;
    reg        quarter_tick;
    reg scl_drive_low;
    reg sda_drive_low;

    assign scl = scl_drive_low ? 1'b0 : 1'bz;
    assign sda = sda_drive_low ? 1'b0 : 1'bz;

    reg sda_meta;
    reg sda_sync;

    always @(posedge clk) begin
        if (reset) begin
            sda_meta <= 1'b1;
            sda_sync <= 1'b1;
        end else begin
            sda_meta <= sda;
            sda_sync <= sda_meta;
        end
    end

    wire sda_in = sda_sync;

    always @(posedge clk) begin
        if (reset) begin
            quarter_counter <= 16'd0;
            quarter_tick    <= 1'b0;
        end else begin
            quarter_tick <= 1'b0;
            if (busy) begin
                if (quarter_counter == QUARTER_COUNT - 1) begin
                    quarter_counter <= 16'd0;
                    quarter_tick    <= 1'b1;
                end else begin
                    quarter_counter <= quarter_counter + 1'b1;
                end
            end else begin
                quarter_counter <= 16'd0;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state          <= ST_IDLE;
            active_command <= CMD_START;
            shift_reg      <= 8'd0;
            rx_data        <= 8'd0;
            bit_index      <= 3'd7;
            phase          <= 2'd0;
            busy           <= 1'b0;
            done           <= 1'b0;
            ack_error      <= 1'b0;
            scl_drive_low  <= 1'b0;
            sda_drive_low  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (command_valid) begin
                        active_command <= command;
                        shift_reg      <= tx_data;
                        bit_index      <= 3'd7;
                        phase          <= 2'd0;
                        busy           <= 1'b1;
                        case (command)
                            CMD_START: state <= ST_START;
                            CMD_STOP: state <= ST_STOP;
                            CMD_WRITE: state <= ST_WRITE_BIT;
                            CMD_READ_ACK, CMD_READ_NACK: begin
                                shift_reg <= 8'd0;
                                state <= ST_READ_BIT;
                            end
                            default: begin
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                ST_START: begin
                    if (quarter_tick) begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b0;
                                phase <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b0;
                                phase <= 2'd2;
                            end
                            2'd2: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b1;
                                phase <= 2'd3;
                            end
                            default: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b1;
                                state <= ST_IDLE;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                ST_STOP: begin
                    if (quarter_tick) begin
                        case (phase)
                            2'd0: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b1; phase <= 2'd1; end
                            2'd1: begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b1; phase <= 2'd2; end
                            2'd2: begin scl_drive_low <= 1'b0; sda_drive_low <= 1'b0; phase <= 2'd3; end
                            default: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b0;
                                state <= ST_IDLE;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                ST_WRITE_BIT: begin
                    if (quarter_tick) begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= ~shift_reg[bit_index];
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_drive_low <= 1'b0; phase <= 2'd2; end
                            2'd2: begin scl_drive_low <= 1'b0; phase <= 2'd3; end
                            default: begin
                                scl_drive_low <= 1'b1;
                                phase <= 2'd0;
                                if (bit_index == 0) begin
                                    sda_drive_low <= 1'b0;
                                    state <= ST_WRITE_ACK;
                                end else begin
                                    bit_index <= bit_index - 1'b1;
                                end
                            end
                        endcase
                    end
                end

                ST_WRITE_ACK: begin
                    if (quarter_tick) begin
                        case (phase)
                            2'd0: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; phase <= 2'd1; end
                            2'd1: begin scl_drive_low <= 1'b0; phase <= 2'd2; end
                            2'd2: begin scl_drive_low <= 1'b0; ack_error <= sda_in; phase <= 2'd3; end
                            default: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b0;
                                state <= ST_IDLE;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                ST_READ_BIT: begin
                    if (quarter_tick) begin
                        case (phase)
                            2'd0: begin scl_drive_low <= 1'b1; sda_drive_low <= 1'b0; phase <= 2'd1; end
                            2'd1: begin scl_drive_low <= 1'b0; phase <= 2'd2; end
                            2'd2: begin
                                scl_drive_low <= 1'b0;
                                shift_reg[bit_index] <= sda_in;
                                phase <= 2'd3;
                            end
                            default: begin
                                scl_drive_low <= 1'b1;
                                phase <= 2'd0;
                                if (bit_index == 0) state <= ST_READ_ACK;
                                else bit_index <= bit_index - 1'b1;
                            end
                        endcase
                    end
                end

                ST_READ_ACK: begin
                    if (quarter_tick) begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= (active_command == CMD_READ_ACK);
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_drive_low <= 1'b0; phase <= 2'd2; end
                            2'd2: begin scl_drive_low <= 1'b0; phase <= 2'd3; end
                            default: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b0;
                                rx_data <= shift_reg;
                                state <= ST_IDLE;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
