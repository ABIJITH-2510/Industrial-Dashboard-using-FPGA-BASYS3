`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// HDC1080 Pmod HYGRO controller
//////////////////////////////////////////////////////////////////////////////////

(* keep_hierarchy = "yes" *) module pmod_hygro_controller #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000
)(
    input  wire        clk,
    input  wire        reset,
    output wire        hyg_scl,
    inout  wire        hyg_sda,
    output reg  [15:0] raw_temperature,
    output reg  [15:0] raw_humidity,
    output reg  signed [15:0] temperature_c_tenths,
    output reg  signed [15:0] temperature_f_tenths,
    output reg         [15:0] humidity_tenths,
    output reg         data_valid,
    output reg         sensor_error,
    output reg         measurement_pulse
);

    localparam [2:0] CMD_START     = 3'd0;
    localparam [2:0] CMD_STOP      = 3'd1;
    localparam [2:0] CMD_WRITE     = 3'd2;
    localparam [2:0] CMD_READ_ACK  = 3'd3;
    localparam [2:0] CMD_READ_NACK = 3'd4;

    localparam [7:0] HYGRO_WRITE_ADDRESS = 8'h80;
    localparam [7:0] HYGRO_READ_ADDRESS  = 8'h81;
    localparam [7:0] TEMPERATURE_POINTER = 8'h00;

    localparam integer POWERUP_WAIT_CYCLES = CLOCK_FREQ_HZ / 50;
    localparam integer CONVERSION_WAIT_CYCLES = CLOCK_FREQ_HZ / 50;
    localparam integer SAMPLE_WAIT_CYCLES = CLOCK_FREQ_HZ;

    localparam [5:0] ST_POWERUP_WAIT  = 6'd0;
    localparam [5:0] ST_START_WRITE   = 6'd1;
    localparam [5:0] ST_SEND_ADDR_W   = 6'd2;
    localparam [5:0] ST_SEND_POINTER  = 6'd3;
    localparam [5:0] ST_STOP_TRIGGER  = 6'd4;
    localparam [5:0] ST_CONVERT_WAIT  = 6'd5;
    localparam [5:0] ST_START_READ    = 6'd6;
    localparam [5:0] ST_SEND_ADDR_R   = 6'd7;
    localparam [5:0] ST_READ_TEMP_MSB = 6'd8;
    localparam [5:0] ST_READ_TEMP_LSB = 6'd9;
    localparam [5:0] ST_READ_HUM_MSB  = 6'd10;
    localparam [5:0] ST_READ_HUM_LSB  = 6'd11;
    localparam [5:0] ST_STOP_READ     = 6'd12;
    localparam [5:0] ST_CALC_SCALE    = 6'd13;
    localparam [5:0] ST_CALC_CONVERT  = 6'd14;
    localparam [5:0] ST_CALC_COMMIT   = 6'd15;
    localparam [5:0] ST_SAMPLE_WAIT   = 6'd16;
    localparam [5:0] ST_RECOVERY_STOP = 6'd17;

    reg [5:0] state;
    reg [31:0] wait_counter;
    reg command_valid;
    reg [2:0] command;
    reg [7:0] tx_data;
    wire [7:0] rx_data;
    wire i2c_busy;
    wire i2c_done;
    wire i2c_ack_error;
    reg command_issued;

    reg [7:0] temp_msb, temp_lsb, hum_msb, hum_lsb;
    reg [31:0] temp_c_scaled, temp_f_scaled, hum_scaled;
    reg signed [15:0] temp_c_pipeline, temp_f_pipeline;

    i2c_master #(.CLOCK_FREQ_HZ(CLOCK_FREQ_HZ), .I2C_FREQ_HZ(100_000)) i2c_bus (
        .clk(clk), .reset(reset),
        .command_valid(command_valid), .command(command), .tx_data(tx_data),
        .rx_data(rx_data), .busy(i2c_busy), .done(i2c_done),
        .ack_error(i2c_ack_error), .scl(hyg_scl), .sda(hyg_sda)
    );

    task launch_command;
        input [2:0] requested_command;
        input [7:0] requested_data;
        begin
            if (!command_issued && !i2c_busy) begin
                command <= requested_command;
                tx_data <= requested_data;
                command_valid <= 1'b1;
                command_issued <= 1'b1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_POWERUP_WAIT;
            wait_counter <= 32'd0;
            command_valid <= 1'b0;
            command <= CMD_START;
            tx_data <= 8'd0;
            command_issued <= 1'b0;
            temp_msb <= 8'd0; temp_lsb <= 8'd0;
            hum_msb <= 8'd0; hum_lsb <= 8'd0;
            raw_temperature <= 16'd0; raw_humidity <= 16'd0;
            temperature_c_tenths <= 16'sd0;
            temperature_f_tenths <= 16'sd0;
            humidity_tenths <= 16'd0;
            temp_c_scaled <= 32'd0; temp_f_scaled <= 32'd0; hum_scaled <= 32'd0;
            temp_c_pipeline <= 16'sd0; temp_f_pipeline <= 16'sd0;
            data_valid <= 1'b0; sensor_error <= 1'b0;
            measurement_pulse <= 1'b0;
        end else begin
            command_valid <= 1'b0;
            measurement_pulse <= 1'b0;

            case (state)
                ST_POWERUP_WAIT: begin
                    if (wait_counter >= POWERUP_WAIT_CYCLES - 1) begin
                        wait_counter <= 32'd0;
                        command_issued <= 1'b0;
                        state <= ST_START_WRITE;
                    end else wait_counter <= wait_counter + 1'b1;
                end

                ST_START_WRITE: begin
                    launch_command(CMD_START, 8'h00);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        state <= ST_SEND_ADDR_W;
                    end
                end

                ST_SEND_ADDR_W: begin
                    launch_command(CMD_WRITE, HYGRO_WRITE_ADDRESS);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        if (i2c_ack_error) begin sensor_error <= 1'b1; state <= ST_RECOVERY_STOP; end
                        else state <= ST_SEND_POINTER;
                    end
                end

                ST_SEND_POINTER: begin
                    launch_command(CMD_WRITE, TEMPERATURE_POINTER);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        if (i2c_ack_error) begin sensor_error <= 1'b1; state <= ST_RECOVERY_STOP; end
                        else state <= ST_STOP_TRIGGER;
                    end
                end

                ST_STOP_TRIGGER: begin
                    launch_command(CMD_STOP, 8'h00);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        wait_counter <= 32'd0;
                        state <= ST_CONVERT_WAIT;
                    end
                end

                ST_CONVERT_WAIT: begin
                    if (wait_counter >= CONVERSION_WAIT_CYCLES - 1) begin
                        wait_counter <= 32'd0;
                        command_issued <= 1'b0;
                        state <= ST_START_READ;
                    end else wait_counter <= wait_counter + 1'b1;
                end

                ST_START_READ: begin
                    launch_command(CMD_START, 8'h00);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        state <= ST_SEND_ADDR_R;
                    end
                end

                ST_SEND_ADDR_R: begin
                    launch_command(CMD_WRITE, HYGRO_READ_ADDRESS);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        if (i2c_ack_error) begin sensor_error <= 1'b1; state <= ST_RECOVERY_STOP; end
                        else state <= ST_READ_TEMP_MSB;
                    end
                end

                ST_READ_TEMP_MSB: begin
                    launch_command(CMD_READ_ACK, 8'h00);
                    if (i2c_done && command_issued) begin
                        temp_msb <= rx_data; command_issued <= 1'b0;
                        state <= ST_READ_TEMP_LSB;
                    end
                end

                ST_READ_TEMP_LSB: begin
                    launch_command(CMD_READ_ACK, 8'h00);
                    if (i2c_done && command_issued) begin
                        temp_lsb <= rx_data; command_issued <= 1'b0;
                        state <= ST_READ_HUM_MSB;
                    end
                end

                ST_READ_HUM_MSB: begin
                    launch_command(CMD_READ_ACK, 8'h00);
                    if (i2c_done && command_issued) begin
                        hum_msb <= rx_data; command_issued <= 1'b0;
                        state <= ST_READ_HUM_LSB;
                    end
                end

                ST_READ_HUM_LSB: begin
                    launch_command(CMD_READ_NACK, 8'h00);
                    if (i2c_done && command_issued) begin
                        hum_lsb <= rx_data; command_issued <= 1'b0;
                        state <= ST_STOP_READ;
                    end
                end

                ST_STOP_READ: begin
                    launch_command(CMD_STOP, 8'h00);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        raw_temperature <= {temp_msb, temp_lsb};
                        raw_humidity <= {hum_msb, hum_lsb};
                        state <= ST_CALC_SCALE;
                    end
                end

                ST_CALC_SCALE: begin
                    temp_c_scaled <= raw_temperature * 32'd1650 + 32'd32768;
                    temp_f_scaled <= raw_temperature * 32'd2970 + 32'd32768;
                    hum_scaled <= raw_humidity * 32'd1000 + 32'd32768;
                    state <= ST_CALC_CONVERT;
                end

                ST_CALC_CONVERT: begin
                    temp_c_pipeline <= $signed(temp_c_scaled[31:16]) - 16'sd400;
                    temp_f_pipeline <= $signed(temp_f_scaled[31:16]) - 16'sd400;
                    humidity_tenths <= hum_scaled[31:16];
                    state <= ST_CALC_COMMIT;
                end

                ST_CALC_COMMIT: begin
                    temperature_c_tenths <= temp_c_pipeline;
                    temperature_f_tenths <= temp_f_pipeline;
                    data_valid <= 1'b1;
                    sensor_error <= 1'b0;
                    measurement_pulse <= 1'b1;
                    wait_counter <= 32'd0;
                    state <= ST_SAMPLE_WAIT;
                end

                ST_SAMPLE_WAIT: begin
                    if (wait_counter >= SAMPLE_WAIT_CYCLES - 1) begin
                        wait_counter <= 32'd0;
                        command_issued <= 1'b0;
                        state <= ST_START_WRITE;
                    end else wait_counter <= wait_counter + 1'b1;
                end

                ST_RECOVERY_STOP: begin
                    launch_command(CMD_STOP, 8'h00);
                    if (i2c_done && command_issued) begin
                        command_issued <= 1'b0;
                        wait_counter <= 32'd0;
                        state <= ST_SAMPLE_WAIT;
                    end
                end

                default: state <= ST_POWERUP_WAIT;
            endcase
        end
    end

endmodule
