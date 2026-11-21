`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Basys 3 Pmod HYGRO Environmental Monitor Top Module
//////////////////////////////////////////////////////////////////////////////////

module top_pmod_hygro_vga (
    input  wire        clk,
    input  wire        btnC,
    input  wire        sw0,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    output wire [3:0]  vgaRed,
    output wire [3:0]  vgaGreen,
    output wire [3:0]  vgaBlue,
    output wire        Hsync,
    output wire        Vsync,
    output wire        hyg_scl,
    inout  wire        hyg_sda,
    output wire        tx
);

    wire [15:0] raw_temperature;
    wire [15:0] raw_humidity;
    wire signed [15:0] temperature_c_tenths;
    wire signed [15:0] temperature_f_tenths;
    wire [15:0] humidity_tenths;
    wire data_valid;
    wire sensor_error;
    wire measurement_pulse;

    reg measurement_toggle;

    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire video_active;

    wire [15:0] selected_display_value =
        sw0 ? humidity_tenths :
        (temperature_f_tenths[15] ? 16'd0 : temperature_f_tenths);

    always @(posedge clk) begin
        if (btnC)
            measurement_toggle <= 1'b0;
        else if (measurement_pulse)
            measurement_toggle <= ~measurement_toggle;
    end

    pmod_hygro_controller #(.CLOCK_FREQ_HZ(100_000_000)) sensor_controller (
        .clk(clk), .reset(btnC),
        .hyg_scl(hyg_scl), .hyg_sda(hyg_sda),
        .raw_temperature(raw_temperature), .raw_humidity(raw_humidity),
        .temperature_c_tenths(temperature_c_tenths),
        .temperature_f_tenths(temperature_f_tenths),
        .humidity_tenths(humidity_tenths),
        .data_valid(data_valid), .sensor_error(sensor_error),
        .measurement_pulse(measurement_pulse)
    );

    vga_640x480 timing (
        .clk(clk), .reset(btnC),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .video_active(video_active),
        .hsync(Hsync), .vsync(Vsync)
    );

    hygro_vga_renderer renderer (
        .pixel_x(pixel_x), .pixel_y(pixel_y), .video_active(video_active),
        .temperature_c_tenths(temperature_c_tenths),
        .temperature_f_tenths(temperature_f_tenths),
        .humidity_tenths(humidity_tenths),
        .data_valid(data_valid), .sensor_error(sensor_error),
        .vga_red(vgaRed), .vga_green(vgaGreen), .vga_blue(vgaBlue)
    );

    seven_segment_display display (
        .clk(clk), .reset(btnC),
        .value_tenths(selected_display_value),
        .blank(!data_valid), .seg(seg), .dp(dp), .an(an)
    );

    assign led[15] = data_valid;
    assign led[14] = sensor_error;
    assign led[13] = sw0;
    assign led[12] = ~sw0;
    assign led[11] = measurement_toggle;
    assign led[10] = data_valid & ~sensor_error;
    assign led[9]  = measurement_toggle;
    assign led[8]  = measurement_pulse;
    assign led[7:0] = sw0 ? raw_humidity[15:8] : raw_temperature[15:8];

    wire tx_busy;
    reg tx_start;
    reg [7:0] tx_data;

    uart_tx #(.CLKS_PER_BIT(10416)) uart_inst (
        .clk(clk), .tx_start(tx_start), .tx_data(tx_data),
        .tx_busy(tx_busy), .tx(tx)
    );

    wire [7:0] temp_int = (temperature_c_tenths >= 0) ? (temperature_c_tenths / 10) : 8'd0;
    wire [7:0] hum_int = humidity_tenths / 10;
    wire [3:0] t_tens = temp_int / 10;
    wire [3:0] t_ones = temp_int % 10;
    wire [3:0] h_tens = hum_int / 10;
    wire [3:0] h_ones = hum_int % 10;

    reg [27:0] timer = 0;
    reg [3:0] byte_count = 0;
    reg [1:0] state = 0;

    localparam S_WAIT_TIMER = 2'd0;
    localparam S_LOAD_BYTE  = 2'd1;
    localparam S_WAIT_BUSY  = 2'd2;
    localparam S_WAIT_FREE  = 2'd3;

    always @(posedge clk) begin
        if (btnC) begin
            timer <= 0;
            byte_count <= 0;
            state <= S_WAIT_TIMER;
            tx_start <= 0;
        end else begin
            case (state)
                S_WAIT_TIMER: begin
                    tx_start <= 0;
                    if (timer >= 100_000_000) begin
                        timer <= 0;
                        byte_count <= 0;
                        if (data_valid) state <= S_LOAD_BYTE;
                    end else timer <= timer + 1;
                end

                S_LOAD_BYTE: begin
                    case (byte_count)
                        4'd0: tx_data <= "T";
                        4'd1: tx_data <= ":";
                        4'd2: tx_data <= t_tens + 8'd48;
                        4'd3: tx_data <= t_ones + 8'd48;
                        4'd4: tx_data <= " ";
                        4'd5: tx_data <= "H";
                        4'd6: tx_data <= ":";
                        4'd7: tx_data <= h_tens + 8'd48;
                        4'd8: tx_data <= h_ones + 8'd48;
                        4'd9: tx_data <= "\n";
                        default: tx_data <= 8'd0;
                    endcase
                    tx_start <= 1;
                    state <= S_WAIT_BUSY;
                end

                S_WAIT_BUSY: begin
                    tx_start <= 0;
                    if (tx_busy) state <= S_WAIT_FREE;
                end

                S_WAIT_FREE: begin
                    if (!tx_busy) begin
                        if (byte_count == 9) state <= S_WAIT_TIMER;
                        else begin
                            byte_count <= byte_count + 1;
                            state <= S_LOAD_BYTE;
                        end
                    end
                end
            endcase
        end
    end

endmodule
