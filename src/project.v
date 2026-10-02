/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 * Base: plantilla VGA de Tiny Tapeout (hvsync_generator).
 *
 * Arreglo plano de parches microstrip con su diagrama de radiacion 3D,
 * vista en perspectiva tipo simulador EM. Todo sale de formulas reales:
 *
 * Diagrama de campo lejano (multiplicacion de patrones, Balanis cap. 6 y 14):
 *   F(u,v)  = EF(u,v) * AF(u,v),  u = sin(th)cos(ph), v = sin(th)sin(ph)
 *   AF      = |sum_m a_m e^{j m k d u}| * |sum_n b_n e^{j n k d v}|  (normalizado)
 *   EF      = |sinc(k W v / 2)| * |cos(k L_ef u / 2)| * sqrt(cos^2(ph) + cos^2(th) sin^2(ph))
 *             (modelo de cavidad: dos ranuras radiantes separadas L_ef)
 *   Grafico polar en dB: radio = H * (G_dB + DR) / DR, color = G_dB.
 *   M x N = 8 x 10, d = 0.5 lambda, parche W = 0.4 lambda, L_ef = 0.38 lambda
 *   taper coseno sobre pedestal 0.6 (lobulo lateral maximo -16.8 dB)
 *   rango dinamico del grafico polar 30 dB; 13 lobulos por encima de -30 dB
 *
 * Cada lobulo se obtuvo con trazado de rayos sobre ese diagrama, con camara
 * ortografica real (azimut atan(1/4), elevacion 30 grados). Las tablas guardan
 * por fila su silueta exacta (borde izquierdo y derecho) y la ganancia de la
 * superficie visible. El orden de pintado sale de la profundidad real.
 * El sombreado lateral es cosmetico (no es iluminacion fisica).
 *
 * Placa: densidad de corriente superficial del modo TM10 de cada parche,
 *   J(x,y,t) = a_m b_n sin(pi x'/L) cos(w t)    (en dB, 0 a -31 dB)
 * con el mismo taper a_m b_n del diagrama. La red de alimentacion microstrip
 * (lineas y troncales) es ilustrativa.
 *
 * Mapeo placa <-> pantalla (camara anterior, plano z = 0, celda = 1024):
 *   P4 = 28 (x - 320) + 14 (y - 284)
 *   Q4 =  7 (x - 320) - 56 (y - 284)
 *
 * Entradas:
 *   ui_in[0]   pausa de la animacion de corriente
 *   ui_in[2:1] velocidad
 *   ui_in[3]   1 = |J| promedio en el tiempo (estatico), 0 = J instantanea
 *   ui_in[4]   ocultar el diagrama (ver la placa completa)
 */
`default_nettype none

module tt_um_vga_example (
  input wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input wire ena,
  input wire clk,
  input wire rst_n
);
  assign uio_out = 8'b0;
  assign uio_oe = 8'b0;

  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  hvsync_generator hvsync_gen (
    .clk(clk), .reset(~rst_n),
    .hsync(hsync), .vsync(vsync), .display_on(video_active),
    .hpos(pix_x), .vpos(pix_y)
  );

  // ---------------------------------------------------------------------
  // Controles sincronizados
  // ---------------------------------------------------------------------
  reg [4:0] ctl_meta, ctl;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctl_meta <= 5'b0;
      ctl <= 5'b0;
    end else begin
      ctl_meta <= ui_in[4:0];
      ctl <= ctl_meta;
    end
  end
  wire       pause      = ctl[0];
  wire [1:0] speed      = ctl[2:1];
  wire       time_avg   = ctl[3];
  wire       hide_lobes = ctl[4];

  // ---------------------------------------------------------------------
  // Fase temporal w t: oscilador de Minsky, osc_c = 1024 cos(w t).
  // 1/16 rad por paso, 1 a 4 pasos por cuadro (en la fila 480).
  // ---------------------------------------------------------------------
  reg signed [12:0] osc_c, osc_s;
  wire step = !pause && (pix_y == 10'd480) && (pix_x <= {8'd0, speed});
  wire signed [12:0] osc_c_next = osc_c - ((osc_s + 13'sd8) >>> 4);
  wire signed [12:0] osc_s_next = osc_s + ((osc_c_next + 13'sd8) >>> 4);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      osc_c <= 13'sd1024;
      osc_s <= 13'sd0;
    end else if (step) begin
      osc_c <= osc_c_next;
      osc_s <= osc_s_next;
    end
  end

  // ---------------------------------------------------------------------
  // Tablas en pasos de 0.5 dB (generadas con Python desde las formulas)
  //   taper_m_db / taper_n_db: -20 log10(a_m), -20 log10(b_n)
  //   sinx_db: -20 log10 sin(pi x'/L) sobre la celda (x'[9:4])
  //   cos_db:  -20 log10 |cos(w t)|, indice |osc_c|[9:4]
  // ---------------------------------------------------------------------
  function [5:0] taper_m_db;
    input [2:0] i;
    begin
      case (i)
        3'd0: taper_m_db = 6'd7; 3'd1: taper_m_db = 6'd3; 3'd2: taper_m_db = 6'd1;
        3'd3: taper_m_db = 6'd0; 3'd4: taper_m_db = 6'd0; 3'd5: taper_m_db = 6'd1;
        3'd6: taper_m_db = 6'd3; 3'd7: taper_m_db = 6'd7;
        default: taper_m_db = 6'd63;
      endcase
    end
  endfunction

  function [5:0] taper_n_db;
    input [3:0] i;
    begin
      case (i)
        4'd0: taper_n_db = 6'd7; 4'd1: taper_n_db = 6'd4; 4'd2: taper_n_db = 6'd2;
        4'd3: taper_n_db = 6'd1; 4'd4: taper_n_db = 6'd0; 4'd5: taper_n_db = 6'd0;
        4'd6: taper_n_db = 6'd1; 4'd7: taper_n_db = 6'd2; 4'd8: taper_n_db = 6'd4;
        4'd9: taper_n_db = 6'd7;
        default: taper_n_db = 6'd63;
      endcase
    end
  endfunction

  function [5:0] sinx_db;
    input [5:0] i;
    begin
      case (i)
        6'd0: sinx_db = 6'd63; 6'd1: sinx_db = 6'd63; 6'd2: sinx_db = 6'd63;
        6'd3: sinx_db = 6'd63; 6'd4: sinx_db = 6'd63; 6'd5: sinx_db = 6'd63;
        6'd6: sinx_db = 6'd63; 6'd7: sinx_db = 6'd63; 6'd8: sinx_db = 6'd63;
        6'd9: sinx_db = 6'd63; 6'd10: sinx_db = 6'd63; 6'd11: sinx_db = 6'd57;
        6'd12: sinx_db = 6'd38; 6'd13: sinx_db = 6'd29; 6'd14: sinx_db = 6'd23;
        6'd15: sinx_db = 6'd19; 6'd16: sinx_db = 6'd16; 6'd17: sinx_db = 6'd13;
        6'd18: sinx_db = 6'd11; 6'd19: sinx_db = 6'd9; 6'd20: sinx_db = 6'd7;
        6'd21: sinx_db = 6'd6; 6'd22: sinx_db = 6'd5; 6'd23: sinx_db = 6'd4;
        6'd24: sinx_db = 6'd3; 6'd25: sinx_db = 6'd2; 6'd26: sinx_db = 6'd2;
        6'd27: sinx_db = 6'd1; 6'd28: sinx_db = 6'd1; 6'd29: sinx_db = 6'd0;
        6'd30: sinx_db = 6'd0; 6'd31: sinx_db = 6'd0; 6'd32: sinx_db = 6'd0;
        6'd33: sinx_db = 6'd0; 6'd34: sinx_db = 6'd0; 6'd35: sinx_db = 6'd1;
        6'd36: sinx_db = 6'd1; 6'd37: sinx_db = 6'd2; 6'd38: sinx_db = 6'd2;
        6'd39: sinx_db = 6'd3; 6'd40: sinx_db = 6'd4; 6'd41: sinx_db = 6'd5;
        6'd42: sinx_db = 6'd6; 6'd43: sinx_db = 6'd7; 6'd44: sinx_db = 6'd9;
        6'd45: sinx_db = 6'd11; 6'd46: sinx_db = 6'd13; 6'd47: sinx_db = 6'd16;
        6'd48: sinx_db = 6'd19; 6'd49: sinx_db = 6'd23; 6'd50: sinx_db = 6'd29;
        6'd51: sinx_db = 6'd38; 6'd52: sinx_db = 6'd57; 6'd53: sinx_db = 6'd63;
        6'd54: sinx_db = 6'd63; 6'd55: sinx_db = 6'd63; 6'd56: sinx_db = 6'd63;
        6'd57: sinx_db = 6'd63; 6'd58: sinx_db = 6'd63; 6'd59: sinx_db = 6'd63;
        6'd60: sinx_db = 6'd63; 6'd61: sinx_db = 6'd63; 6'd62: sinx_db = 6'd63;
        6'd63: sinx_db = 6'd63;
        default: sinx_db = 6'd63;
      endcase
    end
  endfunction

  function [5:0] cos_db;
    input [5:0] i;
    begin
      case (i)
        6'd0: cos_db = 6'd63; 6'd1: cos_db = 6'd63; 6'd2: cos_db = 6'd56;
        6'd3: cos_db = 6'd50; 6'd4: cos_db = 6'd46; 6'd5: cos_db = 6'd43;
        6'd6: cos_db = 6'd40; 6'd7: cos_db = 6'd37; 6'd8: cos_db = 6'd35;
        6'd9: cos_db = 6'd33; 6'd10: cos_db = 6'd31; 6'd11: cos_db = 6'd30;
        6'd12: cos_db = 6'd28; 6'd13: cos_db = 6'd27; 6'd14: cos_db = 6'd26;
        6'd15: cos_db = 6'd25; 6'd16: cos_db = 6'd24; 6'd17: cos_db = 6'd23;
        6'd18: cos_db = 6'd22; 6'd19: cos_db = 6'd21; 6'd20: cos_db = 6'd20;
        6'd21: cos_db = 6'd19; 6'd22: cos_db = 6'd18; 6'd23: cos_db = 6'd17;
        6'd24: cos_db = 6'd17; 6'd25: cos_db = 6'd16; 6'd26: cos_db = 6'd15;
        6'd27: cos_db = 6'd15; 6'd28: cos_db = 6'd14; 6'd29: cos_db = 6'd13;
        6'd30: cos_db = 6'd13; 6'd31: cos_db = 6'd12; 6'd32: cos_db = 6'd12;
        6'd33: cos_db = 6'd11; 6'd34: cos_db = 6'd11; 6'd35: cos_db = 6'd10;
        6'd36: cos_db = 6'd10; 6'd37: cos_db = 6'd9; 6'd38: cos_db = 6'd9;
        6'd39: cos_db = 6'd8; 6'd40: cos_db = 6'd8; 6'd41: cos_db = 6'd8;
        6'd42: cos_db = 6'd7; 6'd43: cos_db = 6'd7; 6'd44: cos_db = 6'd6;
        6'd45: cos_db = 6'd6; 6'd46: cos_db = 6'd6; 6'd47: cos_db = 6'd5;
        6'd48: cos_db = 6'd5; 6'd49: cos_db = 6'd4; 6'd50: cos_db = 6'd4;
        6'd51: cos_db = 6'd4; 6'd52: cos_db = 6'd3; 6'd53: cos_db = 6'd3;
        6'd54: cos_db = 6'd3; 6'd55: cos_db = 6'd2; 6'd56: cos_db = 6'd2;
        6'd57: cos_db = 6'd2; 6'd58: cos_db = 6'd2; 6'd59: cos_db = 6'd1;
        6'd60: cos_db = 6'd1; 6'd61: cos_db = 6'd1; 6'd62: cos_db = 6'd0;
        6'd63: cos_db = 6'd0;
        default: cos_db = 6'd0;
      endcase
    end
  endfunction

  // ---------------------------------------------------------------------
  // Siluetas de los lobulos: {borde izq[7:0], borde der[7:0], nivel[4:0]}
  // ---------------------------------------------------------------------
  // Lobulo 12: (u, v) = (+0.000, +0.693), pico -26.1 dB, 31 filas x 1 px
  function [20:0] lobe12_rom;
    input [4:0] i;
    begin
      case (i)
        5'd0: lobe12_rom = {8'd5, 8'd5, 5'd4}; 5'd1: lobe12_rom = {8'd4, 8'd5, 5'd4}; 5'd2: lobe12_rom = {8'd4, 8'd5, 5'd4};
        5'd3: lobe12_rom = {8'd4, 8'd5, 5'd4}; 5'd4: lobe12_rom = {8'd3, 8'd5, 5'd3}; 5'd5: lobe12_rom = {8'd3, 8'd5, 5'd3};
        5'd6: lobe12_rom = {8'd3, 8'd5, 5'd3}; 5'd7: lobe12_rom = {8'd3, 8'd5, 5'd3}; 5'd8: lobe12_rom = {8'd2, 8'd5, 5'd3};
        5'd9: lobe12_rom = {8'd2, 8'd5, 5'd3}; 5'd10: lobe12_rom = {8'd2, 8'd5, 5'd3}; 5'd11: lobe12_rom = {8'd2, 8'd4, 5'd3};
        5'd12: lobe12_rom = {8'd1, 8'd4, 5'd3}; 5'd13: lobe12_rom = {8'd1, 8'd4, 5'd2}; 5'd14: lobe12_rom = {8'd1, 8'd4, 5'd2};
        5'd15: lobe12_rom = {8'd1, 8'd4, 5'd2}; 5'd16: lobe12_rom = {8'd1, 8'd3, 5'd2}; 5'd17: lobe12_rom = {8'd1, 8'd3, 5'd2};
        5'd18: lobe12_rom = {8'd1, 8'd3, 5'd2}; 5'd19: lobe12_rom = {8'd1, 8'd3, 5'd2}; 5'd20: lobe12_rom = {8'd0, 8'd2, 5'd2};
        5'd21: lobe12_rom = {8'd0, 8'd2, 5'd2}; 5'd22: lobe12_rom = {8'd0, 8'd2, 5'd1}; 5'd23: lobe12_rom = {8'd0, 8'd2, 5'd1};
        5'd24: lobe12_rom = {8'd0, 8'd1, 5'd1}; 5'd25: lobe12_rom = {8'd0, 8'd1, 5'd1}; 5'd26: lobe12_rom = {8'd0, 8'd1, 5'd1};
        5'd27: lobe12_rom = {8'd0, 8'd1, 5'd1}; 5'd28: lobe12_rom = {8'd0, 8'd0, 5'd1}; 5'd29: lobe12_rom = {8'd0, 8'd0, 5'd1};
        5'd30: lobe12_rom = {8'd0, 8'd0, 5'd0};
        default: lobe12_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 3: (u, v) = (-0.863, +0.000), pico -26.9 dB, 15 filas x 1 px
  function [20:0] lobe3_rom;
    input [3:0] i;
    begin
      case (i)
        4'd0: lobe3_rom = {8'd0, 8'd2, 5'd3}; 4'd1: lobe3_rom = {8'd1, 8'd4, 5'd3}; 4'd2: lobe3_rom = {8'd2, 8'd6, 5'd3};
        4'd3: lobe3_rom = {8'd4, 8'd7, 5'd2}; 4'd4: lobe3_rom = {8'd5, 8'd9, 5'd2}; 4'd5: lobe3_rom = {8'd7, 8'd10, 5'd2};
        4'd6: lobe3_rom = {8'd8, 8'd12, 5'd2}; 4'd7: lobe3_rom = {8'd9, 8'd13, 5'd2}; 4'd8: lobe3_rom = {8'd11, 8'd15, 5'd1};
        4'd9: lobe3_rom = {8'd13, 8'd16, 5'd1}; 4'd10: lobe3_rom = {8'd15, 8'd17, 5'd1}; 4'd11: lobe3_rom = {8'd17, 8'd18, 5'd1};
        4'd12: lobe3_rom = {8'd19, 8'd19, 5'd1}; 4'd13: lobe3_rom = {8'd21, 8'd21, 5'd0}; 4'd14: lobe3_rom = {8'd22, 8'd22, 5'd0};
        default: lobe3_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 11: (u, v) = (+0.000, +0.498), pico -21.9 dB, 74 filas x 1 px
  function [20:0] lobe11_rom;
    input [6:0] i;
    begin
      case (i)
        7'd0: lobe11_rom = {8'd9, 8'd9, 5'd8}; 7'd1: lobe11_rom = {8'd7, 8'd10, 5'd8}; 7'd2: lobe11_rom = {8'd7, 8'd10, 5'd8};
        7'd3: lobe11_rom = {8'd6, 8'd11, 5'd8}; 7'd4: lobe11_rom = {8'd6, 8'd11, 5'd8}; 7'd5: lobe11_rom = {8'd5, 8'd11, 5'd8};
        7'd6: lobe11_rom = {8'd5, 8'd11, 5'd8}; 7'd7: lobe11_rom = {8'd4, 8'd12, 5'd8}; 7'd8: lobe11_rom = {8'd4, 8'd12, 5'd7};
        7'd9: lobe11_rom = {8'd4, 8'd12, 5'd7}; 7'd10: lobe11_rom = {8'd4, 8'd12, 5'd7}; 7'd11: lobe11_rom = {8'd3, 8'd12, 5'd7};
        7'd12: lobe11_rom = {8'd3, 8'd12, 5'd7}; 7'd13: lobe11_rom = {8'd3, 8'd12, 5'd7}; 7'd14: lobe11_rom = {8'd3, 8'd12, 5'd7};
        7'd15: lobe11_rom = {8'd2, 8'd12, 5'd7}; 7'd16: lobe11_rom = {8'd2, 8'd12, 5'd7}; 7'd17: lobe11_rom = {8'd2, 8'd12, 5'd6};
        7'd18: lobe11_rom = {8'd2, 8'd12, 5'd6}; 7'd19: lobe11_rom = {8'd2, 8'd12, 5'd6}; 7'd20: lobe11_rom = {8'd2, 8'd11, 5'd6};
        7'd21: lobe11_rom = {8'd1, 8'd11, 5'd6}; 7'd22: lobe11_rom = {8'd1, 8'd11, 5'd6}; 7'd23: lobe11_rom = {8'd1, 8'd11, 5'd6};
        7'd24: lobe11_rom = {8'd1, 8'd11, 5'd6}; 7'd25: lobe11_rom = {8'd1, 8'd11, 5'd6}; 7'd26: lobe11_rom = {8'd1, 8'd11, 5'd5};
        7'd27: lobe11_rom = {8'd1, 8'd11, 5'd5}; 7'd28: lobe11_rom = {8'd1, 8'd11, 5'd5}; 7'd29: lobe11_rom = {8'd1, 8'd10, 5'd5};
        7'd30: lobe11_rom = {8'd1, 8'd10, 5'd5}; 7'd31: lobe11_rom = {8'd0, 8'd10, 5'd5}; 7'd32: lobe11_rom = {8'd0, 8'd10, 5'd5};
        7'd33: lobe11_rom = {8'd0, 8'd10, 5'd5}; 7'd34: lobe11_rom = {8'd0, 8'd10, 5'd5}; 7'd35: lobe11_rom = {8'd0, 8'd9, 5'd4};
        7'd36: lobe11_rom = {8'd0, 8'd9, 5'd4}; 7'd37: lobe11_rom = {8'd0, 8'd9, 5'd4}; 7'd38: lobe11_rom = {8'd0, 8'd9, 5'd4};
        7'd39: lobe11_rom = {8'd0, 8'd9, 5'd4}; 7'd40: lobe11_rom = {8'd0, 8'd8, 5'd4}; 7'd41: lobe11_rom = {8'd0, 8'd8, 5'd4};
        7'd42: lobe11_rom = {8'd0, 8'd8, 5'd4}; 7'd43: lobe11_rom = {8'd0, 8'd8, 5'd4}; 7'd44: lobe11_rom = {8'd0, 8'd8, 5'd3};
        7'd45: lobe11_rom = {8'd0, 8'd7, 5'd3}; 7'd46: lobe11_rom = {8'd0, 8'd7, 5'd3}; 7'd47: lobe11_rom = {8'd0, 8'd7, 5'd3};
        7'd48: lobe11_rom = {8'd0, 8'd7, 5'd3}; 7'd49: lobe11_rom = {8'd0, 8'd6, 5'd3}; 7'd50: lobe11_rom = {8'd0, 8'd6, 5'd3};
        7'd51: lobe11_rom = {8'd0, 8'd6, 5'd3}; 7'd52: lobe11_rom = {8'd0, 8'd6, 5'd2}; 7'd53: lobe11_rom = {8'd0, 8'd6, 5'd2};
        7'd54: lobe11_rom = {8'd0, 8'd5, 5'd2}; 7'd55: lobe11_rom = {8'd0, 8'd5, 5'd2}; 7'd56: lobe11_rom = {8'd0, 8'd5, 5'd2};
        7'd57: lobe11_rom = {8'd0, 8'd4, 5'd2}; 7'd58: lobe11_rom = {8'd0, 8'd4, 5'd2}; 7'd59: lobe11_rom = {8'd0, 8'd4, 5'd2};
        7'd60: lobe11_rom = {8'd0, 8'd4, 5'd2}; 7'd61: lobe11_rom = {8'd0, 8'd3, 5'd1}; 7'd62: lobe11_rom = {8'd0, 8'd3, 5'd1};
        7'd63: lobe11_rom = {8'd0, 8'd3, 5'd1}; 7'd64: lobe11_rom = {8'd0, 8'd2, 5'd1}; 7'd65: lobe11_rom = {8'd0, 8'd2, 5'd1};
        7'd66: lobe11_rom = {8'd0, 8'd2, 5'd1}; 7'd67: lobe11_rom = {8'd0, 8'd2, 5'd1}; 7'd68: lobe11_rom = {8'd0, 8'd1, 5'd1};
        7'd69: lobe11_rom = {8'd0, 8'd1, 5'd1}; 7'd70: lobe11_rom = {8'd0, 8'd1, 5'd0}; 7'd71: lobe11_rom = {8'd0, 8'd0, 5'd0};
        7'd72: lobe11_rom = {8'd0, 8'd0, 5'd0}; 7'd73: lobe11_rom = {8'd0, 8'd0, 5'd0};
        default: lobe11_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 9: (u, v) = (+0.863, +0.000), pico -26.9 dB, 9 filas x 1 px
  function [20:0] lobe9_rom;
    input [3:0] i;
    begin
      case (i)
        4'd0: lobe9_rom = {8'd17, 8'd21, 5'd3}; 4'd1: lobe9_rom = {8'd14, 8'd19, 5'd3}; 4'd2: lobe9_rom = {8'd12, 8'd18, 5'd2};
        4'd3: lobe9_rom = {8'd10, 8'd15, 5'd2}; 4'd4: lobe9_rom = {8'd7, 8'd13, 5'd2}; 4'd5: lobe9_rom = {8'd5, 8'd10, 5'd1};
        4'd6: lobe9_rom = {8'd3, 8'd8, 5'd1}; 4'd7: lobe9_rom = {8'd2, 8'd4, 5'd1}; 4'd8: lobe9_rom = {8'd0, 8'd1, 5'd1};
        default: lobe9_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 4: (u, v) = (-0.620, +0.000), pico -22.2 dB, 53 filas x 1 px
  function [20:0] lobe4_rom;
    input [5:0] i;
    begin
      case (i)
        6'd0: lobe4_rom = {8'd0, 8'd1, 5'd8}; 6'd1: lobe4_rom = {8'd0, 8'd3, 5'd8}; 6'd2: lobe4_rom = {8'd0, 8'd4, 5'd8};
        6'd3: lobe4_rom = {8'd1, 8'd5, 5'd8}; 6'd4: lobe4_rom = {8'd1, 8'd7, 5'd7}; 6'd5: lobe4_rom = {8'd1, 8'd7, 5'd7};
        6'd6: lobe4_rom = {8'd2, 8'd8, 5'd7}; 6'd7: lobe4_rom = {8'd3, 8'd9, 5'd7}; 6'd8: lobe4_rom = {8'd3, 8'd10, 5'd7};
        6'd9: lobe4_rom = {8'd4, 8'd11, 5'd7}; 6'd10: lobe4_rom = {8'd4, 8'd12, 5'd7}; 6'd11: lobe4_rom = {8'd5, 8'd13, 5'd6};
        6'd12: lobe4_rom = {8'd5, 8'd14, 5'd6}; 6'd13: lobe4_rom = {8'd6, 8'd14, 5'd6}; 6'd14: lobe4_rom = {8'd7, 8'd15, 5'd6};
        6'd15: lobe4_rom = {8'd8, 8'd16, 5'd6}; 6'd16: lobe4_rom = {8'd8, 8'd17, 5'd6}; 6'd17: lobe4_rom = {8'd9, 8'd18, 5'd6};
        6'd18: lobe4_rom = {8'd10, 8'd18, 5'd5}; 6'd19: lobe4_rom = {8'd11, 8'd19, 5'd5}; 6'd20: lobe4_rom = {8'd11, 8'd20, 5'd5};
        6'd21: lobe4_rom = {8'd12, 8'd21, 5'd5}; 6'd22: lobe4_rom = {8'd13, 8'd21, 5'd5}; 6'd23: lobe4_rom = {8'd14, 8'd22, 5'd5};
        6'd24: lobe4_rom = {8'd15, 8'd23, 5'd5}; 6'd25: lobe4_rom = {8'd16, 8'd24, 5'd4}; 6'd26: lobe4_rom = {8'd16, 8'd24, 5'd4};
        6'd27: lobe4_rom = {8'd17, 8'd25, 5'd4}; 6'd28: lobe4_rom = {8'd18, 8'd26, 5'd4}; 6'd29: lobe4_rom = {8'd19, 8'd26, 5'd4};
        6'd30: lobe4_rom = {8'd20, 8'd27, 5'd4}; 6'd31: lobe4_rom = {8'd21, 8'd28, 5'd3}; 6'd32: lobe4_rom = {8'd22, 8'd28, 5'd3};
        6'd33: lobe4_rom = {8'd23, 8'd29, 5'd3}; 6'd34: lobe4_rom = {8'd23, 8'd30, 5'd3}; 6'd35: lobe4_rom = {8'd24, 8'd30, 5'd3};
        6'd36: lobe4_rom = {8'd25, 8'd31, 5'd3}; 6'd37: lobe4_rom = {8'd26, 8'd32, 5'd3}; 6'd38: lobe4_rom = {8'd27, 8'd32, 5'd2};
        6'd39: lobe4_rom = {8'd28, 8'd33, 5'd2}; 6'd40: lobe4_rom = {8'd29, 8'd34, 5'd2}; 6'd41: lobe4_rom = {8'd30, 8'd34, 5'd2};
        6'd42: lobe4_rom = {8'd31, 8'd35, 5'd2}; 6'd43: lobe4_rom = {8'd32, 8'd36, 5'd2}; 6'd44: lobe4_rom = {8'd33, 8'd36, 5'd2};
        6'd45: lobe4_rom = {8'd34, 8'd37, 5'd1}; 6'd46: lobe4_rom = {8'd35, 8'd37, 5'd1}; 6'd47: lobe4_rom = {8'd36, 8'd38, 5'd1};
        6'd48: lobe4_rom = {8'd37, 8'd39, 5'd1}; 6'd49: lobe4_rom = {8'd38, 8'd39, 5'd1}; 6'd50: lobe4_rom = {8'd39, 8'd40, 5'd1};
        6'd51: lobe4_rom = {8'd41, 8'd41, 5'd0}; 6'd52: lobe4_rom = {8'd41, 8'd41, 5'd0};
        default: lobe4_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 10: (u, v) = (+0.000, +0.300), pico -16.8 dB, 115 filas x 1 px
  function [20:0] lobe10_rom;
    input [6:0] i;
    begin
      case (i)
        7'd0: lobe10_rom = {8'd13, 8'd13, 5'd14}; 7'd1: lobe10_rom = {8'd11, 8'd16, 5'd14}; 7'd2: lobe10_rom = {8'd10, 8'd17, 5'd13};
        7'd3: lobe10_rom = {8'd9, 8'd17, 5'd13}; 7'd4: lobe10_rom = {8'd9, 8'd18, 5'd13}; 7'd5: lobe10_rom = {8'd8, 8'd18, 5'd13};
        7'd6: lobe10_rom = {8'd7, 8'd19, 5'd13}; 7'd7: lobe10_rom = {8'd7, 8'd19, 5'd13}; 7'd8: lobe10_rom = {8'd6, 8'd20, 5'd13};
        7'd9: lobe10_rom = {8'd6, 8'd20, 5'd13}; 7'd10: lobe10_rom = {8'd5, 8'd20, 5'd13}; 7'd11: lobe10_rom = {8'd5, 8'd20, 5'd12};
        7'd12: lobe10_rom = {8'd5, 8'd21, 5'd12}; 7'd13: lobe10_rom = {8'd4, 8'd21, 5'd12}; 7'd14: lobe10_rom = {8'd4, 8'd21, 5'd12};
        7'd15: lobe10_rom = {8'd4, 8'd21, 5'd12}; 7'd16: lobe10_rom = {8'd4, 8'd21, 5'd12}; 7'd17: lobe10_rom = {8'd3, 8'd21, 5'd12};
        7'd18: lobe10_rom = {8'd3, 8'd22, 5'd12}; 7'd19: lobe10_rom = {8'd3, 8'd22, 5'd12}; 7'd20: lobe10_rom = {8'd3, 8'd22, 5'd11};
        7'd21: lobe10_rom = {8'd2, 8'd22, 5'd11}; 7'd22: lobe10_rom = {8'd2, 8'd22, 5'd11}; 7'd23: lobe10_rom = {8'd2, 8'd22, 5'd11};
        7'd24: lobe10_rom = {8'd2, 8'd22, 5'd11}; 7'd25: lobe10_rom = {8'd2, 8'd22, 5'd11}; 7'd26: lobe10_rom = {8'd2, 8'd22, 5'd11};
        7'd27: lobe10_rom = {8'd1, 8'd22, 5'd11}; 7'd28: lobe10_rom = {8'd1, 8'd22, 5'd10}; 7'd29: lobe10_rom = {8'd1, 8'd22, 5'd10};
        7'd30: lobe10_rom = {8'd1, 8'd22, 5'd10}; 7'd31: lobe10_rom = {8'd1, 8'd22, 5'd10}; 7'd32: lobe10_rom = {8'd1, 8'd22, 5'd10};
        7'd33: lobe10_rom = {8'd1, 8'd22, 5'd10}; 7'd34: lobe10_rom = {8'd1, 8'd22, 5'd10}; 7'd35: lobe10_rom = {8'd1, 8'd22, 5'd10};
        7'd36: lobe10_rom = {8'd1, 8'd22, 5'd10}; 7'd37: lobe10_rom = {8'd1, 8'd22, 5'd9}; 7'd38: lobe10_rom = {8'd0, 8'd22, 5'd9};
        7'd39: lobe10_rom = {8'd0, 8'd22, 5'd9}; 7'd40: lobe10_rom = {8'd0, 8'd22, 5'd9}; 7'd41: lobe10_rom = {8'd0, 8'd22, 5'd9};
        7'd42: lobe10_rom = {8'd0, 8'd21, 5'd9}; 7'd43: lobe10_rom = {8'd0, 8'd21, 5'd9}; 7'd44: lobe10_rom = {8'd0, 8'd21, 5'd9};
        7'd45: lobe10_rom = {8'd0, 8'd21, 5'd9}; 7'd46: lobe10_rom = {8'd0, 8'd21, 5'd8}; 7'd47: lobe10_rom = {8'd0, 8'd21, 5'd8};
        7'd48: lobe10_rom = {8'd0, 8'd21, 5'd8}; 7'd49: lobe10_rom = {8'd0, 8'd21, 5'd8}; 7'd50: lobe10_rom = {8'd0, 8'd21, 5'd8};
        7'd51: lobe10_rom = {8'd0, 8'd20, 5'd8}; 7'd52: lobe10_rom = {8'd0, 8'd20, 5'd8}; 7'd53: lobe10_rom = {8'd0, 8'd20, 5'd8};
        7'd54: lobe10_rom = {8'd0, 8'd20, 5'd7}; 7'd55: lobe10_rom = {8'd0, 8'd20, 5'd7}; 7'd56: lobe10_rom = {8'd0, 8'd20, 5'd7};
        7'd57: lobe10_rom = {8'd0, 8'd19, 5'd7}; 7'd58: lobe10_rom = {8'd0, 8'd19, 5'd7}; 7'd59: lobe10_rom = {8'd0, 8'd19, 5'd7};
        7'd60: lobe10_rom = {8'd0, 8'd19, 5'd7}; 7'd61: lobe10_rom = {8'd0, 8'd19, 5'd7}; 7'd62: lobe10_rom = {8'd0, 8'd19, 5'd7};
        7'd63: lobe10_rom = {8'd0, 8'd18, 5'd6}; 7'd64: lobe10_rom = {8'd0, 8'd18, 5'd6}; 7'd65: lobe10_rom = {8'd0, 8'd18, 5'd6};
        7'd66: lobe10_rom = {8'd0, 8'd18, 5'd6}; 7'd67: lobe10_rom = {8'd0, 8'd18, 5'd6}; 7'd68: lobe10_rom = {8'd0, 8'd18, 5'd6};
        7'd69: lobe10_rom = {8'd0, 8'd17, 5'd6}; 7'd70: lobe10_rom = {8'd0, 8'd17, 5'd6}; 7'd71: lobe10_rom = {8'd0, 8'd17, 5'd6};
        7'd72: lobe10_rom = {8'd1, 8'd17, 5'd5}; 7'd73: lobe10_rom = {8'd1, 8'd16, 5'd5}; 7'd74: lobe10_rom = {8'd1, 8'd16, 5'd5};
        7'd75: lobe10_rom = {8'd1, 8'd16, 5'd5}; 7'd76: lobe10_rom = {8'd1, 8'd16, 5'd5}; 7'd77: lobe10_rom = {8'd1, 8'd16, 5'd5};
        7'd78: lobe10_rom = {8'd1, 8'd15, 5'd5}; 7'd79: lobe10_rom = {8'd1, 8'd15, 5'd5}; 7'd80: lobe10_rom = {8'd1, 8'd15, 5'd4};
        7'd81: lobe10_rom = {8'd1, 8'd15, 5'd4}; 7'd82: lobe10_rom = {8'd1, 8'd15, 5'd4}; 7'd83: lobe10_rom = {8'd1, 8'd14, 5'd4};
        7'd84: lobe10_rom = {8'd1, 8'd14, 5'd4}; 7'd85: lobe10_rom = {8'd2, 8'd14, 5'd4}; 7'd86: lobe10_rom = {8'd2, 8'd13, 5'd4};
        7'd87: lobe10_rom = {8'd2, 8'd13, 5'd4}; 7'd88: lobe10_rom = {8'd2, 8'd13, 5'd4}; 7'd89: lobe10_rom = {8'd2, 8'd13, 5'd3};
        7'd90: lobe10_rom = {8'd2, 8'd12, 5'd3}; 7'd91: lobe10_rom = {8'd2, 8'd12, 5'd3}; 7'd92: lobe10_rom = {8'd2, 8'd12, 5'd3};
        7'd93: lobe10_rom = {8'd2, 8'd12, 5'd3}; 7'd94: lobe10_rom = {8'd2, 8'd11, 5'd3}; 7'd95: lobe10_rom = {8'd3, 8'd11, 5'd3};
        7'd96: lobe10_rom = {8'd3, 8'd11, 5'd3}; 7'd97: lobe10_rom = {8'd3, 8'd11, 5'd2}; 7'd98: lobe10_rom = {8'd3, 8'd10, 5'd2};
        7'd99: lobe10_rom = {8'd3, 8'd10, 5'd2}; 7'd100: lobe10_rom = {8'd3, 8'd10, 5'd2}; 7'd101: lobe10_rom = {8'd3, 8'd10, 5'd2};
        7'd102: lobe10_rom = {8'd3, 8'd9, 5'd2}; 7'd103: lobe10_rom = {8'd3, 8'd9, 5'd2}; 7'd104: lobe10_rom = {8'd4, 8'd9, 5'd2};
        7'd105: lobe10_rom = {8'd4, 8'd8, 5'd2}; 7'd106: lobe10_rom = {8'd4, 8'd8, 5'd1}; 7'd107: lobe10_rom = {8'd4, 8'd8, 5'd1};
        7'd108: lobe10_rom = {8'd4, 8'd8, 5'd1}; 7'd109: lobe10_rom = {8'd4, 8'd7, 5'd1}; 7'd110: lobe10_rom = {8'd4, 8'd7, 5'd1};
        7'd111: lobe10_rom = {8'd5, 8'd7, 5'd1}; 7'd112: lobe10_rom = {8'd5, 8'd6, 5'd1}; 7'd113: lobe10_rom = {8'd5, 8'd6, 5'd1};
        7'd114: lobe10_rom = {8'd5, 8'd6, 5'd0};
        default: lobe10_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 8: (u, v) = (+0.620, +0.000), pico -22.2 dB, 43 filas x 1 px
  function [20:0] lobe8_rom;
    input [5:0] i;
    begin
      case (i)
        6'd0: lobe8_rom = {8'd40, 8'd42, 5'd8}; 6'd1: lobe8_rom = {8'd38, 8'd42, 5'd8}; 6'd2: lobe8_rom = {8'd37, 8'd42, 5'd8};
        6'd3: lobe8_rom = {8'd35, 8'd41, 5'd7}; 6'd4: lobe8_rom = {8'd34, 8'd40, 5'd7}; 6'd5: lobe8_rom = {8'd33, 8'd40, 5'd7};
        6'd6: lobe8_rom = {8'd32, 8'd39, 5'd7}; 6'd7: lobe8_rom = {8'd31, 8'd39, 5'd7}; 6'd8: lobe8_rom = {8'd30, 8'd38, 5'd7};
        6'd9: lobe8_rom = {8'd29, 8'd37, 5'd7}; 6'd10: lobe8_rom = {8'd28, 8'd36, 5'd6}; 6'd11: lobe8_rom = {8'd27, 8'd35, 5'd6};
        6'd12: lobe8_rom = {8'd26, 8'd34, 5'd6}; 6'd13: lobe8_rom = {8'd25, 8'd33, 5'd6}; 6'd14: lobe8_rom = {8'd24, 8'd32, 5'd6};
        6'd15: lobe8_rom = {8'd23, 8'd32, 5'd6}; 6'd16: lobe8_rom = {8'd22, 8'd31, 5'd5}; 6'd17: lobe8_rom = {8'd21, 8'd30, 5'd5};
        6'd18: lobe8_rom = {8'd20, 8'd29, 5'd5}; 6'd19: lobe8_rom = {8'd19, 8'd28, 5'd5}; 6'd20: lobe8_rom = {8'd18, 8'd27, 5'd5};
        6'd21: lobe8_rom = {8'd17, 8'd25, 5'd4}; 6'd22: lobe8_rom = {8'd17, 8'd24, 5'd4}; 6'd23: lobe8_rom = {8'd16, 8'd23, 5'd4};
        6'd24: lobe8_rom = {8'd15, 8'd22, 5'd4}; 6'd25: lobe8_rom = {8'd14, 8'd21, 5'd4}; 6'd26: lobe8_rom = {8'd13, 8'd20, 5'd3};
        6'd27: lobe8_rom = {8'd12, 8'd19, 5'd3}; 6'd28: lobe8_rom = {8'd12, 8'd18, 5'd3}; 6'd29: lobe8_rom = {8'd11, 8'd16, 5'd3};
        6'd30: lobe8_rom = {8'd10, 8'd15, 5'd3}; 6'd31: lobe8_rom = {8'd9, 8'd14, 5'd2}; 6'd32: lobe8_rom = {8'd8, 8'd13, 5'd2};
        6'd33: lobe8_rom = {8'd7, 8'd12, 5'd2}; 6'd34: lobe8_rom = {8'd7, 8'd10, 5'd2}; 6'd35: lobe8_rom = {8'd6, 8'd9, 5'd2};
        6'd36: lobe8_rom = {8'd5, 8'd8, 5'd1}; 6'd37: lobe8_rom = {8'd4, 8'd6, 5'd1}; 6'd38: lobe8_rom = {8'd3, 8'd5, 5'd1};
        6'd39: lobe8_rom = {8'd3, 8'd4, 5'd1}; 6'd40: lobe8_rom = {8'd2, 8'd2, 5'd1}; 6'd41: lobe8_rom = {8'd1, 8'd1, 5'd0};
        6'd42: lobe8_rom = {8'd0, 8'd0, 5'd0};
        default: lobe8_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 5: (u, v) = (-0.375, +0.000), pico -16.9 dB, 101 filas x 1 px
  function [20:0] lobe5_rom;
    input [6:0] i;
    begin
      case (i)
        7'd0: lobe5_rom = {8'd1, 8'd3, 5'd13}; 7'd1: lobe5_rom = {8'd1, 8'd4, 5'd13}; 7'd2: lobe5_rom = {8'd0, 8'd5, 5'd13};
        7'd3: lobe5_rom = {8'd0, 8'd6, 5'd13}; 7'd4: lobe5_rom = {8'd0, 8'd7, 5'd13}; 7'd5: lobe5_rom = {8'd0, 8'd8, 5'd13};
        7'd6: lobe5_rom = {8'd0, 8'd9, 5'd13}; 7'd7: lobe5_rom = {8'd1, 8'd9, 5'd13}; 7'd8: lobe5_rom = {8'd1, 8'd10, 5'd13};
        7'd9: lobe5_rom = {8'd1, 8'd10, 5'd12}; 7'd10: lobe5_rom = {8'd1, 8'd11, 5'd12}; 7'd11: lobe5_rom = {8'd1, 8'd12, 5'd12};
        7'd12: lobe5_rom = {8'd1, 8'd12, 5'd12}; 7'd13: lobe5_rom = {8'd2, 8'd13, 5'd12}; 7'd14: lobe5_rom = {8'd2, 8'd13, 5'd12};
        7'd15: lobe5_rom = {8'd2, 8'd14, 5'd12}; 7'd16: lobe5_rom = {8'd2, 8'd14, 5'd12}; 7'd17: lobe5_rom = {8'd2, 8'd15, 5'd12};
        7'd18: lobe5_rom = {8'd3, 8'd15, 5'd11}; 7'd19: lobe5_rom = {8'd3, 8'd16, 5'd11}; 7'd20: lobe5_rom = {8'd4, 8'd16, 5'd11};
        7'd21: lobe5_rom = {8'd4, 8'd17, 5'd11}; 7'd22: lobe5_rom = {8'd4, 8'd17, 5'd11}; 7'd23: lobe5_rom = {8'd4, 8'd18, 5'd11};
        7'd24: lobe5_rom = {8'd5, 8'd18, 5'd11}; 7'd25: lobe5_rom = {8'd5, 8'd18, 5'd11}; 7'd26: lobe5_rom = {8'd5, 8'd19, 5'd10};
        7'd27: lobe5_rom = {8'd6, 8'd19, 5'd10}; 7'd28: lobe5_rom = {8'd6, 8'd20, 5'd10}; 7'd29: lobe5_rom = {8'd7, 8'd20, 5'd10};
        7'd30: lobe5_rom = {8'd7, 8'd21, 5'd10}; 7'd31: lobe5_rom = {8'd7, 8'd21, 5'd10}; 7'd32: lobe5_rom = {8'd8, 8'd21, 5'd10};
        7'd33: lobe5_rom = {8'd8, 8'd22, 5'd10}; 7'd34: lobe5_rom = {8'd9, 8'd22, 5'd9}; 7'd35: lobe5_rom = {8'd9, 8'd23, 5'd9};
        7'd36: lobe5_rom = {8'd9, 8'd23, 5'd9}; 7'd37: lobe5_rom = {8'd10, 8'd23, 5'd9}; 7'd38: lobe5_rom = {8'd10, 8'd24, 5'd9};
        7'd39: lobe5_rom = {8'd11, 8'd24, 5'd9}; 7'd40: lobe5_rom = {8'd11, 8'd25, 5'd9}; 7'd41: lobe5_rom = {8'd12, 8'd25, 5'd8};
        7'd42: lobe5_rom = {8'd12, 8'd25, 5'd8}; 7'd43: lobe5_rom = {8'd12, 8'd26, 5'd8}; 7'd44: lobe5_rom = {8'd13, 8'd26, 5'd8};
        7'd45: lobe5_rom = {8'd13, 8'd26, 5'd8}; 7'd46: lobe5_rom = {8'd14, 8'd27, 5'd8}; 7'd47: lobe5_rom = {8'd14, 8'd27, 5'd8};
        7'd48: lobe5_rom = {8'd15, 8'd28, 5'd8}; 7'd49: lobe5_rom = {8'd15, 8'd28, 5'd7}; 7'd50: lobe5_rom = {8'd16, 8'd28, 5'd7};
        7'd51: lobe5_rom = {8'd16, 8'd29, 5'd7}; 7'd52: lobe5_rom = {8'd17, 8'd29, 5'd7}; 7'd53: lobe5_rom = {8'd17, 8'd29, 5'd7};
        7'd54: lobe5_rom = {8'd18, 8'd30, 5'd7}; 7'd55: lobe5_rom = {8'd18, 8'd30, 5'd7}; 7'd56: lobe5_rom = {8'd19, 8'd30, 5'd6};
        7'd57: lobe5_rom = {8'd19, 8'd31, 5'd6}; 7'd58: lobe5_rom = {8'd20, 8'd31, 5'd6}; 7'd59: lobe5_rom = {8'd20, 8'd31, 5'd6};
        7'd60: lobe5_rom = {8'd21, 8'd32, 5'd6}; 7'd61: lobe5_rom = {8'd21, 8'd32, 5'd6}; 7'd62: lobe5_rom = {8'd22, 8'd32, 5'd6};
        7'd63: lobe5_rom = {8'd22, 8'd33, 5'd5}; 7'd64: lobe5_rom = {8'd23, 8'd33, 5'd5}; 7'd65: lobe5_rom = {8'd24, 8'd33, 5'd5};
        7'd66: lobe5_rom = {8'd24, 8'd34, 5'd5}; 7'd67: lobe5_rom = {8'd25, 8'd34, 5'd5}; 7'd68: lobe5_rom = {8'd25, 8'd34, 5'd5};
        7'd69: lobe5_rom = {8'd26, 8'd35, 5'd5}; 7'd70: lobe5_rom = {8'd26, 8'd35, 5'd5}; 7'd71: lobe5_rom = {8'd27, 8'd35, 5'd4};
        7'd72: lobe5_rom = {8'd27, 8'd36, 5'd4}; 7'd73: lobe5_rom = {8'd28, 8'd36, 5'd4}; 7'd74: lobe5_rom = {8'd28, 8'd36, 5'd4};
        7'd75: lobe5_rom = {8'd29, 8'd36, 5'd4}; 7'd76: lobe5_rom = {8'd30, 8'd37, 5'd4}; 7'd77: lobe5_rom = {8'd30, 8'd37, 5'd4};
        7'd78: lobe5_rom = {8'd31, 8'd37, 5'd3}; 7'd79: lobe5_rom = {8'd31, 8'd38, 5'd3}; 7'd80: lobe5_rom = {8'd32, 8'd38, 5'd3};
        7'd81: lobe5_rom = {8'd33, 8'd38, 5'd3}; 7'd82: lobe5_rom = {8'd33, 8'd39, 5'd3}; 7'd83: lobe5_rom = {8'd34, 8'd39, 5'd3};
        7'd84: lobe5_rom = {8'd34, 8'd39, 5'd3}; 7'd85: lobe5_rom = {8'd35, 8'd39, 5'd2}; 7'd86: lobe5_rom = {8'd36, 8'd40, 5'd2};
        7'd87: lobe5_rom = {8'd36, 8'd40, 5'd2}; 7'd88: lobe5_rom = {8'd37, 8'd40, 5'd2}; 7'd89: lobe5_rom = {8'd37, 8'd41, 5'd2};
        7'd90: lobe5_rom = {8'd38, 8'd41, 5'd2}; 7'd91: lobe5_rom = {8'd39, 8'd41, 5'd2}; 7'd92: lobe5_rom = {8'd39, 8'd42, 5'd1};
        7'd93: lobe5_rom = {8'd40, 8'd42, 5'd1}; 7'd94: lobe5_rom = {8'd40, 8'd42, 5'd1}; 7'd95: lobe5_rom = {8'd41, 8'd42, 5'd1};
        7'd96: lobe5_rom = {8'd42, 8'd43, 5'd1}; 7'd97: lobe5_rom = {8'd42, 8'd43, 5'd1}; 7'd98: lobe5_rom = {8'd43, 8'd43, 5'd1};
        7'd99: lobe5_rom = {8'd44, 8'd44, 5'd0}; 7'd100: lobe5_rom = {8'd44, 8'd44, 5'd0};
        default: lobe5_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 7: (u, v) = (+0.375, +0.000), pico -16.9 dB, 90 filas x 1 px
  function [20:0] lobe7_rom;
    input [6:0] i;
    begin
      case (i)
        7'd0: lobe7_rom = {8'd41, 8'd43, 5'd13}; 7'd1: lobe7_rom = {8'd40, 8'd43, 5'd13}; 7'd2: lobe7_rom = {8'd39, 8'd44, 5'd13};
        7'd3: lobe7_rom = {8'd38, 8'd44, 5'd13}; 7'd4: lobe7_rom = {8'd37, 8'd44, 5'd13}; 7'd5: lobe7_rom = {8'd36, 8'd43, 5'd13};
        7'd6: lobe7_rom = {8'd36, 8'd43, 5'd13}; 7'd7: lobe7_rom = {8'd35, 8'd43, 5'd13}; 7'd8: lobe7_rom = {8'd34, 8'd43, 5'd13};
        7'd9: lobe7_rom = {8'd34, 8'd43, 5'd13}; 7'd10: lobe7_rom = {8'd33, 8'd43, 5'd12}; 7'd11: lobe7_rom = {8'd32, 8'd42, 5'd12};
        7'd12: lobe7_rom = {8'd32, 8'd42, 5'd12}; 7'd13: lobe7_rom = {8'd31, 8'd42, 5'd12}; 7'd14: lobe7_rom = {8'd31, 8'd41, 5'd12};
        7'd15: lobe7_rom = {8'd30, 8'd41, 5'd12}; 7'd16: lobe7_rom = {8'd30, 8'd41, 5'd12}; 7'd17: lobe7_rom = {8'd29, 8'd40, 5'd12};
        7'd18: lobe7_rom = {8'd29, 8'd40, 5'd11}; 7'd19: lobe7_rom = {8'd28, 8'd40, 5'd11}; 7'd20: lobe7_rom = {8'd28, 8'd39, 5'd11};
        7'd21: lobe7_rom = {8'd27, 8'd39, 5'd11}; 7'd22: lobe7_rom = {8'd27, 8'd38, 5'd11}; 7'd23: lobe7_rom = {8'd26, 8'd38, 5'd11};
        7'd24: lobe7_rom = {8'd26, 8'd38, 5'd11}; 7'd25: lobe7_rom = {8'd25, 8'd37, 5'd10}; 7'd26: lobe7_rom = {8'd25, 8'd37, 5'd10};
        7'd27: lobe7_rom = {8'd24, 8'd36, 5'd10}; 7'd28: lobe7_rom = {8'd24, 8'd36, 5'd10}; 7'd29: lobe7_rom = {8'd23, 8'd35, 5'd10};
        7'd30: lobe7_rom = {8'd23, 8'd35, 5'd10}; 7'd31: lobe7_rom = {8'd22, 8'd35, 5'd10}; 7'd32: lobe7_rom = {8'd22, 8'd34, 5'd9};
        7'd33: lobe7_rom = {8'd22, 8'd34, 5'd9}; 7'd34: lobe7_rom = {8'd21, 8'd33, 5'd9}; 7'd35: lobe7_rom = {8'd21, 8'd33, 5'd9};
        7'd36: lobe7_rom = {8'd20, 8'd32, 5'd9}; 7'd37: lobe7_rom = {8'd20, 8'd32, 5'd9}; 7'd38: lobe7_rom = {8'd19, 8'd31, 5'd9};
        7'd39: lobe7_rom = {8'd19, 8'd31, 5'd8}; 7'd40: lobe7_rom = {8'd19, 8'd30, 5'd8}; 7'd41: lobe7_rom = {8'd18, 8'd30, 5'd8};
        7'd42: lobe7_rom = {8'd18, 8'd29, 5'd8}; 7'd43: lobe7_rom = {8'd17, 8'd28, 5'd8}; 7'd44: lobe7_rom = {8'd17, 8'd28, 5'd8};
        7'd45: lobe7_rom = {8'd17, 8'd27, 5'd7}; 7'd46: lobe7_rom = {8'd16, 8'd27, 5'd7}; 7'd47: lobe7_rom = {8'd16, 8'd26, 5'd7};
        7'd48: lobe7_rom = {8'd15, 8'd26, 5'd7}; 7'd49: lobe7_rom = {8'd15, 8'd25, 5'd7}; 7'd50: lobe7_rom = {8'd15, 8'd25, 5'd7};
        7'd51: lobe7_rom = {8'd14, 8'd24, 5'd7}; 7'd52: lobe7_rom = {8'd14, 8'd23, 5'd6}; 7'd53: lobe7_rom = {8'd13, 8'd23, 5'd6};
        7'd54: lobe7_rom = {8'd13, 8'd22, 5'd6}; 7'd55: lobe7_rom = {8'd13, 8'd22, 5'd6}; 7'd56: lobe7_rom = {8'd12, 8'd21, 5'd6};
        7'd57: lobe7_rom = {8'd12, 8'd20, 5'd6}; 7'd58: lobe7_rom = {8'd11, 8'd20, 5'd5}; 7'd59: lobe7_rom = {8'd11, 8'd19, 5'd5};
        7'd60: lobe7_rom = {8'd11, 8'd19, 5'd5}; 7'd61: lobe7_rom = {8'd10, 8'd18, 5'd5}; 7'd62: lobe7_rom = {8'd10, 8'd17, 5'd5};
        7'd63: lobe7_rom = {8'd10, 8'd17, 5'd5}; 7'd64: lobe7_rom = {8'd9, 8'd16, 5'd5}; 7'd65: lobe7_rom = {8'd9, 8'd16, 5'd4};
        7'd66: lobe7_rom = {8'd8, 8'd15, 5'd4}; 7'd67: lobe7_rom = {8'd8, 8'd14, 5'd4}; 7'd68: lobe7_rom = {8'd8, 8'd14, 5'd4};
        7'd69: lobe7_rom = {8'd7, 8'd13, 5'd4}; 7'd70: lobe7_rom = {8'd7, 8'd12, 5'd4}; 7'd71: lobe7_rom = {8'd7, 8'd12, 5'd3};
        7'd72: lobe7_rom = {8'd6, 8'd11, 5'd3}; 7'd73: lobe7_rom = {8'd6, 8'd10, 5'd3}; 7'd74: lobe7_rom = {8'd6, 8'd10, 5'd3};
        7'd75: lobe7_rom = {8'd5, 8'd9, 5'd3}; 7'd76: lobe7_rom = {8'd5, 8'd8, 5'd3}; 7'd77: lobe7_rom = {8'd4, 8'd8, 5'd2};
        7'd78: lobe7_rom = {8'd4, 8'd7, 5'd2}; 7'd79: lobe7_rom = {8'd4, 8'd7, 5'd2}; 7'd80: lobe7_rom = {8'd3, 8'd6, 5'd2};
        7'd81: lobe7_rom = {8'd3, 8'd5, 5'd2}; 7'd82: lobe7_rom = {8'd3, 8'd5, 5'd2}; 7'd83: lobe7_rom = {8'd2, 8'd4, 5'd1};
        7'd84: lobe7_rom = {8'd2, 8'd3, 5'd1}; 7'd85: lobe7_rom = {8'd2, 8'd3, 5'd1}; 7'd86: lobe7_rom = {8'd1, 8'd2, 5'd1};
        7'd87: lobe7_rom = {8'd1, 8'd1, 5'd1}; 7'd88: lobe7_rom = {8'd1, 8'd1, 5'd1}; 7'd89: lobe7_rom = {8'd0, 8'd0, 5'd0};
        default: lobe7_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 6: (u, v) = (+0.000, +0.000), pico 0.0 dB, 121 filas x 2 px
  function [20:0] lobe6_rom;
    input [6:0] i;
    begin
      case (i)
        7'd0: lobe6_rom = {8'd29, 8'd44, 5'd31}; 7'd1: lobe6_rom = {8'd24, 8'd48, 5'd31}; 7'd2: lobe6_rom = {8'd22, 8'd51, 5'd31};
        7'd3: lobe6_rom = {8'd19, 8'd53, 5'd31}; 7'd4: lobe6_rom = {8'd18, 8'd55, 5'd31}; 7'd5: lobe6_rom = {8'd16, 8'd57, 5'd30};
        7'd6: lobe6_rom = {8'd14, 8'd58, 5'd30}; 7'd7: lobe6_rom = {8'd13, 8'd60, 5'd30}; 7'd8: lobe6_rom = {8'd12, 8'd61, 5'd30};
        7'd9: lobe6_rom = {8'd11, 8'd62, 5'd30}; 7'd10: lobe6_rom = {8'd10, 8'd63, 5'd30}; 7'd11: lobe6_rom = {8'd9, 8'd64, 5'd29};
        7'd12: lobe6_rom = {8'd8, 8'd65, 5'd29}; 7'd13: lobe6_rom = {8'd7, 8'd66, 5'd29}; 7'd14: lobe6_rom = {8'd7, 8'd67, 5'd29};
        7'd15: lobe6_rom = {8'd6, 8'd67, 5'd29}; 7'd16: lobe6_rom = {8'd5, 8'd68, 5'd28}; 7'd17: lobe6_rom = {8'd5, 8'd69, 5'd28};
        7'd18: lobe6_rom = {8'd4, 8'd69, 5'd28}; 7'd19: lobe6_rom = {8'd4, 8'd70, 5'd28}; 7'd20: lobe6_rom = {8'd3, 8'd70, 5'd28};
        7'd21: lobe6_rom = {8'd3, 8'd71, 5'd27}; 7'd22: lobe6_rom = {8'd3, 8'd71, 5'd27}; 7'd23: lobe6_rom = {8'd2, 8'd71, 5'd27};
        7'd24: lobe6_rom = {8'd2, 8'd72, 5'd27}; 7'd25: lobe6_rom = {8'd2, 8'd72, 5'd26}; 7'd26: lobe6_rom = {8'd1, 8'd72, 5'd26};
        7'd27: lobe6_rom = {8'd1, 8'd73, 5'd26}; 7'd28: lobe6_rom = {8'd1, 8'd73, 5'd26}; 7'd29: lobe6_rom = {8'd1, 8'd73, 5'd26};
        7'd30: lobe6_rom = {8'd1, 8'd73, 5'd25}; 7'd31: lobe6_rom = {8'd1, 8'd73, 5'd25}; 7'd32: lobe6_rom = {8'd1, 8'd73, 5'd25};
        7'd33: lobe6_rom = {8'd0, 8'd74, 5'd25}; 7'd34: lobe6_rom = {8'd0, 8'd74, 5'd24}; 7'd35: lobe6_rom = {8'd0, 8'd74, 5'd24};
        7'd36: lobe6_rom = {8'd0, 8'd74, 5'd24}; 7'd37: lobe6_rom = {8'd0, 8'd74, 5'd24}; 7'd38: lobe6_rom = {8'd0, 8'd74, 5'd23};
        7'd39: lobe6_rom = {8'd0, 8'd74, 5'd23}; 7'd40: lobe6_rom = {8'd1, 8'd73, 5'd23}; 7'd41: lobe6_rom = {8'd1, 8'd73, 5'd23};
        7'd42: lobe6_rom = {8'd1, 8'd73, 5'd22}; 7'd43: lobe6_rom = {8'd1, 8'd73, 5'd22}; 7'd44: lobe6_rom = {8'd1, 8'd73, 5'd22};
        7'd45: lobe6_rom = {8'd1, 8'd73, 5'd22}; 7'd46: lobe6_rom = {8'd1, 8'd73, 5'd21}; 7'd47: lobe6_rom = {8'd1, 8'd73, 5'd21};
        7'd48: lobe6_rom = {8'd1, 8'd73, 5'd21}; 7'd49: lobe6_rom = {8'd2, 8'd72, 5'd21}; 7'd50: lobe6_rom = {8'd2, 8'd72, 5'd20};
        7'd51: lobe6_rom = {8'd2, 8'd72, 5'd20}; 7'd52: lobe6_rom = {8'd2, 8'd72, 5'd20}; 7'd53: lobe6_rom = {8'd2, 8'd71, 5'd19};
        7'd54: lobe6_rom = {8'd3, 8'd71, 5'd19}; 7'd55: lobe6_rom = {8'd3, 8'd71, 5'd19}; 7'd56: lobe6_rom = {8'd3, 8'd71, 5'd19};
        7'd57: lobe6_rom = {8'd3, 8'd70, 5'd18}; 7'd58: lobe6_rom = {8'd4, 8'd70, 5'd18}; 7'd59: lobe6_rom = {8'd4, 8'd70, 5'd18};
        7'd60: lobe6_rom = {8'd4, 8'd69, 5'd18}; 7'd61: lobe6_rom = {8'd5, 8'd69, 5'd17}; 7'd62: lobe6_rom = {8'd5, 8'd69, 5'd17};
        7'd63: lobe6_rom = {8'd5, 8'd68, 5'd17}; 7'd64: lobe6_rom = {8'd6, 8'd68, 5'd17}; 7'd65: lobe6_rom = {8'd6, 8'd68, 5'd16};
        7'd66: lobe6_rom = {8'd6, 8'd67, 5'd16}; 7'd67: lobe6_rom = {8'd7, 8'd67, 5'd16}; 7'd68: lobe6_rom = {8'd7, 8'd66, 5'd15};
        7'd69: lobe6_rom = {8'd8, 8'd66, 5'd15}; 7'd70: lobe6_rom = {8'd8, 8'd65, 5'd15}; 7'd71: lobe6_rom = {8'd9, 8'd65, 5'd15};
        7'd72: lobe6_rom = {8'd9, 8'd65, 5'd14}; 7'd73: lobe6_rom = {8'd9, 8'd64, 5'd14}; 7'd74: lobe6_rom = {8'd10, 8'd64, 5'd14};
        7'd75: lobe6_rom = {8'd10, 8'd63, 5'd13}; 7'd76: lobe6_rom = {8'd11, 8'd63, 5'd13}; 7'd77: lobe6_rom = {8'd11, 8'd62, 5'd13};
        7'd78: lobe6_rom = {8'd12, 8'd62, 5'd13}; 7'd79: lobe6_rom = {8'd12, 8'd61, 5'd12}; 7'd80: lobe6_rom = {8'd13, 8'd61, 5'd12};
        7'd81: lobe6_rom = {8'd13, 8'd60, 5'd12}; 7'd82: lobe6_rom = {8'd14, 8'd60, 5'd11}; 7'd83: lobe6_rom = {8'd14, 8'd59, 5'd11};
        7'd84: lobe6_rom = {8'd15, 8'd59, 5'd11}; 7'd85: lobe6_rom = {8'd15, 8'd58, 5'd10}; 7'd86: lobe6_rom = {8'd16, 8'd58, 5'd10};
        7'd87: lobe6_rom = {8'd16, 8'd57, 5'd10}; 7'd88: lobe6_rom = {8'd17, 8'd56, 5'd10}; 7'd89: lobe6_rom = {8'd17, 8'd56, 5'd9};
        7'd90: lobe6_rom = {8'd18, 8'd55, 5'd9}; 7'd91: lobe6_rom = {8'd18, 8'd55, 5'd9}; 7'd92: lobe6_rom = {8'd19, 8'd54, 5'd8};
        7'd93: lobe6_rom = {8'd20, 8'd54, 5'd8}; 7'd94: lobe6_rom = {8'd20, 8'd53, 5'd8}; 7'd95: lobe6_rom = {8'd21, 8'd52, 5'd7};
        7'd96: lobe6_rom = {8'd21, 8'd52, 5'd7}; 7'd97: lobe6_rom = {8'd22, 8'd51, 5'd7}; 7'd98: lobe6_rom = {8'd23, 8'd51, 5'd7};
        7'd99: lobe6_rom = {8'd23, 8'd50, 5'd6}; 7'd100: lobe6_rom = {8'd24, 8'd50, 5'd6}; 7'd101: lobe6_rom = {8'd24, 8'd49, 5'd6};
        7'd102: lobe6_rom = {8'd25, 8'd48, 5'd5}; 7'd103: lobe6_rom = {8'd26, 8'd48, 5'd5}; 7'd104: lobe6_rom = {8'd26, 8'd47, 5'd5};
        7'd105: lobe6_rom = {8'd27, 8'd46, 5'd4}; 7'd106: lobe6_rom = {8'd28, 8'd46, 5'd4}; 7'd107: lobe6_rom = {8'd28, 8'd45, 5'd4};
        7'd108: lobe6_rom = {8'd29, 8'd45, 5'd4}; 7'd109: lobe6_rom = {8'd30, 8'd44, 5'd3}; 7'd110: lobe6_rom = {8'd30, 8'd43, 5'd3};
        7'd111: lobe6_rom = {8'd31, 8'd43, 5'd3}; 7'd112: lobe6_rom = {8'd32, 8'd42, 5'd2}; 7'd113: lobe6_rom = {8'd32, 8'd41, 5'd2};
        7'd114: lobe6_rom = {8'd33, 8'd41, 5'd2}; 7'd115: lobe6_rom = {8'd34, 8'd40, 5'd1}; 7'd116: lobe6_rom = {8'd34, 8'd39, 5'd1};
        7'd117: lobe6_rom = {8'd35, 8'd39, 5'd1}; 7'd118: lobe6_rom = {8'd36, 8'd38, 5'd1}; 7'd119: lobe6_rom = {8'd37, 8'd37, 5'd0};
        7'd120: lobe6_rom = {8'd37, 8'd37, 5'd0};
        default: lobe6_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 2: (u, v) = (+0.000, -0.300), pico -16.8 dB, 81 filas x 1 px
  function [20:0] lobe2_rom;
    input [6:0] i;
    begin
      case (i)
        7'd0: lobe2_rom = {8'd5, 8'd10, 5'd14}; 7'd1: lobe2_rom = {8'd4, 8'd12, 5'd13}; 7'd2: lobe2_rom = {8'd3, 8'd13, 5'd13};
        7'd3: lobe2_rom = {8'd3, 8'd14, 5'd13}; 7'd4: lobe2_rom = {8'd2, 8'd15, 5'd13}; 7'd5: lobe2_rom = {8'd2, 8'd15, 5'd13};
        7'd6: lobe2_rom = {8'd1, 8'd16, 5'd13}; 7'd7: lobe2_rom = {8'd1, 8'd16, 5'd13}; 7'd8: lobe2_rom = {8'd1, 8'd17, 5'd13};
        7'd9: lobe2_rom = {8'd1, 8'd17, 5'd12}; 7'd10: lobe2_rom = {8'd0, 8'd18, 5'd12}; 7'd11: lobe2_rom = {8'd0, 8'd18, 5'd12};
        7'd12: lobe2_rom = {8'd0, 8'd18, 5'd12}; 7'd13: lobe2_rom = {8'd0, 8'd19, 5'd12}; 7'd14: lobe2_rom = {8'd0, 8'd19, 5'd12};
        7'd15: lobe2_rom = {8'd0, 8'd19, 5'd12}; 7'd16: lobe2_rom = {8'd0, 8'd20, 5'd11}; 7'd17: lobe2_rom = {8'd0, 8'd20, 5'd11};
        7'd18: lobe2_rom = {8'd0, 8'd20, 5'd11}; 7'd19: lobe2_rom = {8'd0, 8'd20, 5'd11}; 7'd20: lobe2_rom = {8'd0, 8'd21, 5'd11};
        7'd21: lobe2_rom = {8'd0, 8'd21, 5'd11}; 7'd22: lobe2_rom = {8'd0, 8'd21, 5'd10}; 7'd23: lobe2_rom = {8'd0, 8'd21, 5'd10};
        7'd24: lobe2_rom = {8'd0, 8'd21, 5'd10}; 7'd25: lobe2_rom = {8'd0, 8'd21, 5'd10}; 7'd26: lobe2_rom = {8'd0, 8'd21, 5'd10};
        7'd27: lobe2_rom = {8'd1, 8'd22, 5'd10}; 7'd28: lobe2_rom = {8'd1, 8'd22, 5'd10}; 7'd29: lobe2_rom = {8'd1, 8'd22, 5'd9};
        7'd30: lobe2_rom = {8'd1, 8'd22, 5'd9}; 7'd31: lobe2_rom = {8'd1, 8'd22, 5'd9}; 7'd32: lobe2_rom = {8'd1, 8'd22, 5'd9};
        7'd33: lobe2_rom = {8'd1, 8'd22, 5'd9}; 7'd34: lobe2_rom = {8'd2, 8'd22, 5'd8}; 7'd35: lobe2_rom = {8'd2, 8'd22, 5'd8};
        7'd36: lobe2_rom = {8'd2, 8'd22, 5'd8}; 7'd37: lobe2_rom = {8'd2, 8'd22, 5'd8}; 7'd38: lobe2_rom = {8'd2, 8'd22, 5'd8};
        7'd39: lobe2_rom = {8'd3, 8'd22, 5'd8}; 7'd40: lobe2_rom = {8'd3, 8'd22, 5'd8}; 7'd41: lobe2_rom = {8'd3, 8'd22, 5'd7};
        7'd42: lobe2_rom = {8'd3, 8'd22, 5'd7}; 7'd43: lobe2_rom = {8'd4, 8'd22, 5'd7}; 7'd44: lobe2_rom = {8'd4, 8'd22, 5'd7};
        7'd45: lobe2_rom = {8'd4, 8'd22, 5'd7}; 7'd46: lobe2_rom = {8'd4, 8'd22, 5'd6}; 7'd47: lobe2_rom = {8'd5, 8'd22, 5'd6};
        7'd48: lobe2_rom = {8'd5, 8'd22, 5'd6}; 7'd49: lobe2_rom = {8'd5, 8'd22, 5'd6}; 7'd50: lobe2_rom = {8'd6, 8'd22, 5'd6};
        7'd51: lobe2_rom = {8'd6, 8'd21, 5'd6}; 7'd52: lobe2_rom = {8'd6, 8'd21, 5'd5}; 7'd53: lobe2_rom = {8'd7, 8'd21, 5'd5};
        7'd54: lobe2_rom = {8'd7, 8'd21, 5'd5}; 7'd55: lobe2_rom = {8'd7, 8'd21, 5'd5}; 7'd56: lobe2_rom = {8'd7, 8'd21, 5'd5};
        7'd57: lobe2_rom = {8'd8, 8'd21, 5'd5}; 7'd58: lobe2_rom = {8'd8, 8'd21, 5'd4}; 7'd59: lobe2_rom = {8'd8, 8'd21, 5'd4};
        7'd60: lobe2_rom = {8'd9, 8'd20, 5'd4}; 7'd61: lobe2_rom = {8'd9, 8'd20, 5'd4}; 7'd62: lobe2_rom = {8'd10, 8'd20, 5'd4};
        7'd63: lobe2_rom = {8'd10, 8'd20, 5'd3}; 7'd64: lobe2_rom = {8'd10, 8'd20, 5'd3}; 7'd65: lobe2_rom = {8'd11, 8'd20, 5'd3};
        7'd66: lobe2_rom = {8'd11, 8'd20, 5'd3}; 7'd67: lobe2_rom = {8'd11, 8'd19, 5'd3}; 7'd68: lobe2_rom = {8'd12, 8'd19, 5'd3};
        7'd69: lobe2_rom = {8'd12, 8'd19, 5'd2}; 7'd70: lobe2_rom = {8'd13, 8'd19, 5'd2}; 7'd71: lobe2_rom = {8'd13, 8'd19, 5'd2};
        7'd72: lobe2_rom = {8'd13, 8'd19, 5'd2}; 7'd73: lobe2_rom = {8'd14, 8'd18, 5'd2}; 7'd74: lobe2_rom = {8'd14, 8'd18, 5'd1};
        7'd75: lobe2_rom = {8'd15, 8'd18, 5'd1}; 7'd76: lobe2_rom = {8'd15, 8'd18, 5'd1}; 7'd77: lobe2_rom = {8'd15, 8'd18, 5'd1};
        7'd78: lobe2_rom = {8'd16, 8'd17, 5'd1}; 7'd79: lobe2_rom = {8'd16, 8'd17, 5'd1}; 7'd80: lobe2_rom = {8'd17, 8'd17, 5'd0};
        default: lobe2_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 1: (u, v) = (+0.000, -0.497), pico -21.9 dB, 38 filas x 1 px
  function [20:0] lobe1_rom;
    input [5:0] i;
    begin
      case (i)
        6'd0: lobe1_rom = {8'd2, 8'd4, 5'd8}; 6'd1: lobe1_rom = {8'd1, 8'd5, 5'd8}; 6'd2: lobe1_rom = {8'd1, 8'd6, 5'd8};
        6'd3: lobe1_rom = {8'd0, 8'd7, 5'd8}; 6'd4: lobe1_rom = {8'd0, 8'd8, 5'd8}; 6'd5: lobe1_rom = {8'd0, 8'd8, 5'd8};
        6'd6: lobe1_rom = {8'd0, 8'd9, 5'd7}; 6'd7: lobe1_rom = {8'd0, 8'd9, 5'd7}; 6'd8: lobe1_rom = {8'd0, 8'd9, 5'd7};
        6'd9: lobe1_rom = {8'd0, 8'd10, 5'd7}; 6'd10: lobe1_rom = {8'd1, 8'd10, 5'd7}; 6'd11: lobe1_rom = {8'd1, 8'd10, 5'd6};
        6'd12: lobe1_rom = {8'd1, 8'd11, 5'd6}; 6'd13: lobe1_rom = {8'd1, 8'd11, 5'd6}; 6'd14: lobe1_rom = {8'd1, 8'd11, 5'd6};
        6'd15: lobe1_rom = {8'd2, 8'd11, 5'd6}; 6'd16: lobe1_rom = {8'd2, 8'd11, 5'd5}; 6'd17: lobe1_rom = {8'd2, 8'd12, 5'd5};
        6'd18: lobe1_rom = {8'd3, 8'd12, 5'd5}; 6'd19: lobe1_rom = {8'd3, 8'd12, 5'd5}; 6'd20: lobe1_rom = {8'd3, 8'd12, 5'd4};
        6'd21: lobe1_rom = {8'd4, 8'd12, 5'd4}; 6'd22: lobe1_rom = {8'd4, 8'd12, 5'd4}; 6'd23: lobe1_rom = {8'd5, 8'd12, 5'd4};
        6'd24: lobe1_rom = {8'd5, 8'd12, 5'd3}; 6'd25: lobe1_rom = {8'd6, 8'd12, 5'd3}; 6'd26: lobe1_rom = {8'd6, 8'd12, 5'd3};
        6'd27: lobe1_rom = {8'd6, 8'd12, 5'd3}; 6'd28: lobe1_rom = {8'd7, 8'd12, 5'd3}; 6'd29: lobe1_rom = {8'd7, 8'd12, 5'd2};
        6'd30: lobe1_rom = {8'd8, 8'd12, 5'd2}; 6'd31: lobe1_rom = {8'd9, 8'd12, 5'd2}; 6'd32: lobe1_rom = {8'd9, 8'd12, 5'd2};
        6'd33: lobe1_rom = {8'd10, 8'd12, 5'd1}; 6'd34: lobe1_rom = {8'd10, 8'd12, 5'd1}; 6'd35: lobe1_rom = {8'd11, 8'd12, 5'd1};
        6'd36: lobe1_rom = {8'd11, 8'd12, 5'd0}; 6'd37: lobe1_rom = {8'd12, 8'd12, 5'd0};
        default: lobe1_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // Lobulo 0: (u, v) = (+0.000, -0.693), pico -26.1 dB, 10 filas x 1 px
  function [20:0] lobe0_rom;
    input [3:0] i;
    begin
      case (i)
        4'd0: lobe0_rom = {8'd0, 8'd1, 5'd4}; 4'd1: lobe0_rom = {8'd0, 8'd2, 5'd4}; 4'd2: lobe0_rom = {8'd0, 8'd3, 5'd3};
        4'd3: lobe0_rom = {8'd0, 8'd3, 5'd3}; 4'd4: lobe0_rom = {8'd1, 8'd4, 5'd3}; 4'd5: lobe0_rom = {8'd2, 8'd4, 5'd2};
        4'd6: lobe0_rom = {8'd3, 8'd5, 5'd2}; 4'd7: lobe0_rom = {8'd3, 8'd5, 5'd1}; 4'd8: lobe0_rom = {8'd4, 8'd5, 5'd1};
        4'd9: lobe0_rom = {8'd5, 8'd5, 5'd0};
        default: lobe0_rom = {8'd1, 8'd0, 5'd0};
      endcase
    end
  endfunction

  // ---------------------------------------------------------------------
  // Etapa 0a: lobulos (las tablas solo dependen de la fila)
  // ---------------------------------------------------------------------
  wire [9:0] lb12_dy = pix_y - 10'd250;
  wire [20:0] lb12_e = lobe12_rom(lb12_dy[4:0]);
  wire signed [10:0] lb12_xr = $signed({1'b0, pix_x}) - 11'sd321;
  wire lb12_hit = !hide_lobes && (lb12_dy < 10'd31) &&
                   (lb12_xr >= $signed({3'b0, lb12_e[20:13]})) && (lb12_xr <= $signed({3'b0, lb12_e[12:5]}));

  wire [9:0] lb3_dy = pix_y - 10'd269;
  wire [20:0] lb3_e = lobe3_rom(lb3_dy[3:0]);
  wire signed [10:0] lb3_xr = $signed({1'b0, pix_x}) - 11'sd296;
  wire lb3_hit = !hide_lobes && (lb3_dy < 10'd15) &&
                   (lb3_xr >= $signed({3'b0, lb3_e[20:13]})) && (lb3_xr <= $signed({3'b0, lb3_e[12:5]}));

  wire [9:0] lb11_dy = pix_y - 10'd210;
  wire [20:0] lb11_e = lobe11_rom(lb11_dy[6:0]);
  wire signed [10:0] lb11_xr = $signed({1'b0, pix_x}) - 11'sd320;
  wire lb11_hit = !hide_lobes && (lb11_dy < 10'd74) &&
                   (lb11_xr >= $signed({3'b0, lb11_e[20:13]})) && (lb11_xr <= $signed({3'b0, lb11_e[12:5]}));

  wire [9:0] lb9_dy = pix_y - 10'd275;
  wire [20:0] lb9_e = lobe9_rom(lb9_dy[3:0]);
  wire signed [10:0] lb9_xr = $signed({1'b0, pix_x}) - 11'sd323;
  wire lb9_hit = !hide_lobes && (lb9_dy < 10'd9) &&
                   (lb9_xr >= $signed({3'b0, lb9_e[20:13]})) && (lb9_xr <= $signed({3'b0, lb9_e[12:5]}));

  wire [9:0] lb4_dy = pix_y - 10'd230;
  wire [20:0] lb4_e = lobe4_rom(lb4_dy[5:0]);
  wire signed [10:0] lb4_xr = $signed({1'b0, pix_x}) - 11'sd277;
  wire lb4_hit = !hide_lobes && (lb4_dy < 10'd53) &&
                   (lb4_xr >= $signed({3'b0, lb4_e[20:13]})) && (lb4_xr <= $signed({3'b0, lb4_e[12:5]}));

  wire [9:0] lb10_dy = pix_y - 10'd166;
  wire [20:0] lb10_e = lobe10_rom(lb10_dy[6:0]);
  wire signed [10:0] lb10_xr = $signed({1'b0, pix_x}) - 11'sd315;
  wire lb10_hit = !hide_lobes && (lb10_dy < 10'd115) &&
                   (lb10_xr >= $signed({3'b0, lb10_e[20:13]})) && (lb10_xr <= $signed({3'b0, lb10_e[12:5]}));

  wire [9:0] lb8_dy = pix_y - 10'd241;
  wire [20:0] lb8_e = lobe8_rom(lb8_dy[5:0]);
  wire signed [10:0] lb8_xr = $signed({1'b0, pix_x}) - 11'sd321;
  wire lb8_hit = !hide_lobes && (lb8_dy < 10'd43) &&
                   (lb8_xr >= $signed({3'b0, lb8_e[20:13]})) && (lb8_xr <= $signed({3'b0, lb8_e[12:5]}));

  wire [9:0] lb5_dy = pix_y - 10'd182;
  wire [20:0] lb5_e = lobe5_rom(lb5_dy[6:0]);
  wire signed [10:0] lb5_xr = $signed({1'b0, pix_x}) - 11'sd275;
  wire lb5_hit = !hide_lobes && (lb5_dy < 10'd101) &&
                   (lb5_xr >= $signed({3'b0, lb5_e[20:13]})) && (lb5_xr <= $signed({3'b0, lb5_e[12:5]}));

  wire [9:0] lb7_dy = pix_y - 10'd193;
  wire [20:0] lb7_e = lobe7_rom(lb7_dy[6:0]);
  wire signed [10:0] lb7_xr = $signed({1'b0, pix_x}) - 11'sd321;
  wire lb7_hit = !hide_lobes && (lb7_dy < 10'd90) &&
                   (lb7_xr >= $signed({3'b0, lb7_e[20:13]})) && (lb7_xr <= $signed({3'b0, lb7_e[12:5]}));

  wire [9:0] lb6_dy = pix_y - 10'd43;
  wire [20:0] lb6_e = lobe6_rom(lb6_dy[7:1]);
  wire signed [10:0] lb6_xr = $signed({1'b0, pix_x}) - 11'sd283;
  wire lb6_hit = !hide_lobes && (lb6_dy < 10'd242) &&
                   (lb6_xr >= $signed({3'b0, lb6_e[20:13]})) && (lb6_xr <= $signed({3'b0, lb6_e[12:5]}));

  wire [9:0] lb2_dy = pix_y - 10'd202;
  wire [20:0] lb2_e = lobe2_rom(lb2_dy[6:0]);
  wire signed [10:0] lb2_xr = $signed({1'b0, pix_x}) - 11'sd303;
  wire lb2_hit = !hide_lobes && (lb2_dy < 10'd81) &&
                   (lb2_xr >= $signed({3'b0, lb2_e[20:13]})) && (lb2_xr <= $signed({3'b0, lb2_e[12:5]}));

  wire [9:0] lb1_dy = pix_y - 10'd246;
  wire [20:0] lb1_e = lobe1_rom(lb1_dy[5:0]);
  wire signed [10:0] lb1_xr = $signed({1'b0, pix_x}) - 11'sd308;
  wire lb1_hit = !hide_lobes && (lb1_dy < 10'd38) &&
                   (lb1_xr >= $signed({3'b0, lb1_e[20:13]})) && (lb1_xr <= $signed({3'b0, lb1_e[12:5]}));

  wire [9:0] lb0_dy = pix_y - 10'd274;
  wire [20:0] lb0_e = lobe0_rom(lb0_dy[3:0]);
  wire signed [10:0] lb0_xr = $signed({1'b0, pix_x}) - 11'sd314;
  wire lb0_hit = !hide_lobes && (lb0_dy < 10'd10) &&
                   (lb0_xr >= $signed({3'b0, lb0_e[20:13]})) && (lb0_xr <= $signed({3'b0, lb0_e[12:5]}));

  // Orden del pintor (de atras hacia delante): el ultimo que acierta gana
  reg w_hit;
  reg [20:0] w_e;
  reg signed [10:0] w_xr;
  always @* begin
    w_hit = 1'b0;
    w_e = 21'd0;
    w_xr = 11'sd0;
    if (lb12_hit) begin w_hit = 1'b1; w_e = lb12_e; w_xr = lb12_xr; end
    if (lb3_hit) begin w_hit = 1'b1; w_e = lb3_e; w_xr = lb3_xr; end
    if (lb11_hit) begin w_hit = 1'b1; w_e = lb11_e; w_xr = lb11_xr; end
    if (lb9_hit) begin w_hit = 1'b1; w_e = lb9_e; w_xr = lb9_xr; end
    if (lb4_hit) begin w_hit = 1'b1; w_e = lb4_e; w_xr = lb4_xr; end
    if (lb10_hit) begin w_hit = 1'b1; w_e = lb10_e; w_xr = lb10_xr; end
    if (lb8_hit) begin w_hit = 1'b1; w_e = lb8_e; w_xr = lb8_xr; end
    if (lb5_hit) begin w_hit = 1'b1; w_e = lb5_e; w_xr = lb5_xr; end
    if (lb7_hit) begin w_hit = 1'b1; w_e = lb7_e; w_xr = lb7_xr; end
    if (lb6_hit) begin w_hit = 1'b1; w_e = lb6_e; w_xr = lb6_xr; end
    if (lb2_hit) begin w_hit = 1'b1; w_e = lb2_e; w_xr = lb2_xr; end
    if (lb1_hit) begin w_hit = 1'b1; w_e = lb1_e; w_xr = lb1_xr; end
    if (lb0_hit) begin w_hit = 1'b1; w_e = lb0_e; w_xr = lb0_xr; end
  end
  wire [7:0] w_left  = w_e[20:13];
  wire [7:0] w_right = w_e[12:5];
  // s = posicion lateral (de -w a +w), w = ancho de la fila
  wire signed [11:0] lat_s = $signed({w_xr, 1'b0}) - $signed({4'b0, w_left}) - $signed({4'b0, w_right});
  wire [7:0] lat_w = w_right - w_left;

  // ---------------------------------------------------------------------
  // Etapa 0b: placa (coordenadas de placa desde la pantalla)
  // ---------------------------------------------------------------------
  wire signed [17:0] xr = $signed({8'b0, pix_x}) - 18'sd320;
  wire signed [17:0] yd = $signed({8'b0, pix_y}) - 18'sd284;
  wire signed [17:0] pm = (xr <<< 5) - (xr <<< 2) + (yd <<< 4) - (yd <<< 1) + 18'sd4096;  // 28x + 14y
  wire signed [17:0] qn = (xr <<< 3) - xr - (yd <<< 6) + (yd <<< 3) + 18'sd5120;         //  7x - 56y

  function in_board;
    input signed [17:0] p;
    input signed [17:0] q;
    begin
      in_board = (p >= -18'sd512) && (p < 18'sd8704) && (q >= -18'sd512) && (q < 18'sd10752);
    end
  endfunction
  wire on_top  = in_board(pm, qn);
  wire on_side = in_board(pm - 18'sd84, qn + 18'sd336);    // canto del sustrato (6 px)
  wire on_gnd  = in_board(pm - 18'sd126, qn + 18'sd504);   // plano de tierra (9 px)
  wire in_arr  = (pm >= 18'sd0) && (pm < 18'sd8192) && (qn >= 18'sd0) && (qn < 18'sd10240);
  wire [2:0] el_m = pm[12:10];
  wire [3:0] el_n = qn[13:10];
  wire [9:0] lx = pm[9:0];
  wire [9:0] ly = qn[9:0];
  wire patch = (lx >= 10'd176) && (lx < 10'd848) && (ly >= 10'd104) && (ly < 10'd920);
  wire stub  = (lx < 10'd176) && (ly >= 10'd480) && (ly < 10'd544);
  wire bus   = (lx < 10'd48);
  wire [5:0] j_db = patch ? sinx_db(lx[9:4]) : (stub ? 6'd6 : 6'd8);
  wire [7:0] board_db = taper_m_db(el_m) + taper_n_db(el_n) + j_db;
  wire [2:0] board_code = (on_top && in_arr && (patch || stub || bus)) ? 3'd4 :
                          on_top ? 3'd3 : on_side ? 3'd2 : on_gnd ? 3'd1 : 3'd0;
  wire [10:0] xy = pix_x + pix_y;
  wire [3:0] bg = 4'd11 - (pix_y >= 10'd400) - (xy[4:3] == 2'b00);

  // Registro de etapa 1
  reg s1_hit;
  reg signed [11:0] s1_s;
  reg [7:0] s1_w;
  reg [4:0] s1_lev;
  reg [2:0] s1_code;
  reg [7:0] s1_bdb;
  reg [3:0] s1_bg;
  reg [1:0] s1_lsb;
  reg s1_hs, s1_vs, s1_de;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_hit <= 1'b0; s1_s <= 12'sd0; s1_w <= 8'd0; s1_lev <= 5'd0;
      s1_code <= 3'd0; s1_bdb <= 8'd0; s1_bg <= 4'd0; s1_lsb <= 2'd0;
      s1_hs <= 1'b0; s1_vs <= 1'b0; s1_de <= 1'b0;
    end else begin
      s1_hit <= w_hit; s1_s <= lat_s; s1_w <= lat_w; s1_lev <= w_e[4:0];
      s1_code <= board_code; s1_bdb <= board_db; s1_bg <= bg; s1_lsb <= {pix_x[0], pix_y[0]};
      s1_hs <= hsync; s1_vs <= vsync; s1_de <= video_active;
    end
  end

  // ---------------------------------------------------------------------
  // Etapa 1: color
  // ---------------------------------------------------------------------
  // Paleta de falso color: 0 = azul (-31 dB) ... 31 = rojo (0 dB)
  function [11:0] heat_color;
    input [4:0] lv;
    reg [3:0] a;
    begin
      a = {lv[2:0], 1'b0};
      case (lv[4:3])
        2'd0: heat_color = {4'd3, a, 4'd15};
        2'd1: heat_color = {4'd0, 4'd15, (4'd14 - a)};
        2'd2: heat_color = {a, 4'd15, 4'd0};
        default: heat_color = {4'd15, (4'd14 - a), 4'd0};
      endcase
    end
  endfunction

  function [3:0] darken;          // c * (1 - k/8)
    input [3:0] c;
    input [2:0] k;
    reg [6:0] p;
    begin
      p = c * k;
      darken = c - p[6:3];
    end
  endfunction

  function [3:0] lighten;         // c + (15 - c)/4
    input [3:0] c;
    begin
      lighten = c + ((4'd15 - c) >> 2);
    end
  endfunction

  // Sombreado lateral: mas oscuro hacia los bordes y del lado derecho
  wire [11:0] la = s1_s[11] ? -s1_s : s1_s;
  wire [11:0] lw = {4'd0, s1_w};
  wire s_pos = !s1_s[11] && (s1_s != 12'sd0);
  wire [2:0] dk = ({la[10:0], 1'b0} >= lw) + ((la << 2) >= (lw + (lw << 1))) +
                  ((la << 3) >= ((lw << 3) - lw)) + s_pos;
  wire edge_px = (lw >= 12'd3) && (la >= lw - 12'd1);
  wire hilite = ((la << 2) < lw) && !s_pos;
  wire [11:0] lc = heat_color(s1_lev);
  wire [3:0] lr = darken(lc[11:8], dk);
  wire [3:0] lg = darken(lc[7:4], dk);
  wire [3:0] lb = darken(lc[3:0], dk);
  wire [11:0] lobe_rgb = edge_px ? 12'h111 :
                         hilite ? {lighten(lr), lighten(lg), lighten(lb)} : {lr, lg, lb};

  // Corriente: suma en dB de la distribucion espacial y del factor temporal
  wire [12:0] oc_abs = osc_c[12] ? -osc_c : osc_c;
  wire [5:0] t_db = (time_avg || (oc_abs >= 13'd1024)) ? 6'd0 : cos_db(oc_abs[9:4]);
  wire [8:0] j_tot = s1_bdb + t_db;
  wire [5:0] j_clip = (j_tot > 9'd63) ? 6'd63 : j_tot[5:0];
  wire [4:0] j_lev = 5'd31 - j_clip[5:1];

  reg [11:0] rgb;
  always @* begin
    case (s1_code)
      3'd1: rgb = 12'h316;                    // plano de tierra
      3'd2: rgb = 12'h62b;                    // canto del sustrato
      3'd3: rgb = 12'h31a;                    // sustrato visto desde arriba
      3'd4: rgb = heat_color(j_lev);          // cobre con corriente
      default: rgb = {s1_bg, s1_bg, s1_bg};   // fondo
    endcase
    if (s1_hit) rgb = lobe_rgb;
  end

  // Registro de etapa 2
  reg [11:0] s2_rgb;
  reg [1:0] s2_lsb;
  reg s2_hs, s2_vs, s2_de;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s2_rgb <= 12'd0; s2_lsb <= 2'd0;
      s2_hs <= 1'b0; s2_vs <= 1'b0; s2_de <= 1'b0;
    end else begin
      s2_rgb <= rgb; s2_lsb <= s1_lsb;
      s2_hs <= s1_hs; s2_vs <= s1_vs; s2_de <= s1_de;
    end
  end

  // ---------------------------------------------------------------------
  // Etapa 2: tramado ordenado 2 x 2 a 2 bits por canal (TinyVGA) y salida
  // ---------------------------------------------------------------------
  wire [1:0] threshold = {s2_lsb[1], 1'b0} ^ (s2_lsb[0] ? 2'd3 : 2'd0);
  function [1:0] quantize;
    input [3:0] value;
    input [1:0] threshold_value;
    begin
      if ((value[3:2] != 2'd3) && (value[1:0] > threshold_value))
        quantize = value[3:2] + 2'd1;
      else quantize = value[3:2];
    end
  endfunction
  wire [1:0] R = s2_de ? quantize(s2_rgb[11:8], threshold) : 2'd0;
  wire [1:0] G = s2_de ? quantize(s2_rgb[7:4], threshold) : 2'd0;
  wire [1:0] B = s2_de ? quantize(s2_rgb[3:0], threshold) : 2'd0;

  reg [7:0] uo_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) uo_q <= 8'b0;
    else uo_q <= {s2_hs, B[0], G[0], R[0], s2_vs, B[1], G[1], R[1]};
  end
  assign uo_out = uo_q;

  wire _unused_ok = &{1'b0, ena, uio_in, ui_in[7:5], oc_abs[3:0], xy[10:5], xy[2:0]};
endmodule

`default_nettype wire