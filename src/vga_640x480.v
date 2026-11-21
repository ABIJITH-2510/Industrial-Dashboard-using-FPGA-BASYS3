`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// VGA 640x480 timing generator
//////////////////////////////////////////////////////////////////////////////////

(* keep_hierarchy = "yes" *) module vga_640x480 (
    input  wire       clk,
    input  wire       reset,
    output reg  [9:0] pixel_x,
    output reg  [9:0] pixel_y,
    output wire       video_active,
    output wire       hsync,
    output wire       vsync
);

    reg [1:0] pixel_divider;
    wire pixel_tick = (pixel_divider == 2'd3);

    always @(posedge clk) begin
        if (reset)
            pixel_divider <= 2'd0;
        else
            pixel_divider <= pixel_divider + 1'b1;
    end

    always @(posedge clk) begin
        if (reset) begin
            pixel_x <= 10'd0;
            pixel_y <= 10'd0;
        end else if (pixel_tick) begin
            if (pixel_x == 10'd799) begin
                pixel_x <= 10'd0;
                if (pixel_y == 10'd524)
                    pixel_y <= 10'd0;
                else
                    pixel_y <= pixel_y + 1'b1;
            end else begin
                pixel_x <= pixel_x + 1'b1;
            end
        end
    end

    assign video_active = (pixel_x < 10'd640) && (pixel_y < 10'd480);
    assign hsync = ~((pixel_x >= 10'd656) && (pixel_x < 10'd752));
    assign vsync = ~((pixel_y >= 10'd490) && (pixel_y < 10'd492));

endmodule
