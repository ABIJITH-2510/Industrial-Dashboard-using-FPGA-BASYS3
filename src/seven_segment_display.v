`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Seven-segment display driver
//////////////////////////////////////////////////////////////////////////////////

module seven_segment_display (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] value_tenths,
    input  wire        blank,
    output reg  [6:0]  seg,
    output reg         dp,
    output reg  [3:0]  an
);

    reg [16:0] refresh_counter;
    wire [1:0] active_digit = refresh_counter[16:15];
    reg [3:0] digit_value;
    reg [15:0] limited_value;
    reg [3:0] thousands, hundreds, tens, ones;

    always @* begin
        if (value_tenths > 16'd9999)
            limited_value = 16'd9999;
        else
            limited_value = value_tenths;
        thousands = limited_value / 1000;
        hundreds = (limited_value % 1000) / 100;
        tens = (limited_value % 100) / 10;
        ones = limited_value % 10;
    end

    always @(posedge clk) begin
        if (reset)
            refresh_counter <= 17'd0;
        else
            refresh_counter <= refresh_counter + 1'b1;
    end

    always @* begin
        an = 4'b1111;
        dp = 1'b1;
        digit_value = 4'd0;

        if (!blank) begin
            case (active_digit)
                2'd0: begin an = 4'b1110; digit_value = ones; dp = 1'b1; end
                2'd1: begin an = 4'b1101; digit_value = tens; dp = 1'b0; end
                2'd2: begin an = 4'b1011; digit_value = hundreds; dp = 1'b1; end
                default: begin
                    an = 4'b0111;
                    digit_value = thousands;
                    dp = 1'b1;
                    if (thousands == 0) an = 4'b1111;
                end
            endcase
        end

        case (digit_value)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            default: seg = 7'b1111111;
        endcase
    end

endmodule
