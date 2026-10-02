/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 *
 * Parche microstrip (1x1) con su diagrama de radiacion 3D, pensado para un tile 1x1.
 *
 * Antena: FR4 (er = 4.4, h = 1.6 mm) a 2.4 GHz, W = 38.0 mm, L = 29.4 mm,
 * alimentacion por linea de 50 ohm con inserto (formulas de diseno de Balanis).
 *
 * Diagrama (modelo de cavidad, dos ranuras radiantes, plano de tierra infinito):
 *   F = |sin(kW/2 sin(t) sin(p)) / (kW/2 sin(t) sin(p))| * |cos(kLe/2 sin(t) cos(p))|
 *       * sqrt(cos^2(p) + cos^2(t) sin^2(p))
 *   Grafico polar en dB: radio = (G + 20 dB) / 20 dB, color de 0 a -12 dB.
 *   La silueta del lobulo se calculo con trazado de rayos (camara a 30 grados) y
 *   se guarda por filas en lobe_rom: {borde izq, borde der, color}.
 *
 * Corriente en el cobre (modo TM10): J = sin(pi x/L) cos(w t), en dB.
 *
 * Entradas: ui_in[0] = |J| promedio (estatico), ui_in[1] = diagrama translucido,
 *           ui_in[2] = ocultar diagrama.
 */
`default_nettype none

module tt_um_LURAYD_IRRADIATION_ANTENNAv6 (
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  hvsync_generator hvsync_gen (
    .clk(clk), .reset(~rst_n),
    .hsync(hsync), .vsync(vsync), .display_on(video_active),
    .hpos(pix_x), .vpos(pix_y)
  );

  wire avg   = ui_in[0];
  wire glass = ui_in[1];
  wire hide  = ui_in[2];

  // Fase de w t: 64 pasos por ciclo, avanza una vez por cuadro
  reg [5:0] t;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) t <= 6'd0;
    else if (pix_x == 10'd0 && pix_y == 10'd480) t <= t + 6'd1;

  // ---------------- Tablas (generadas desde las formulas) ----------------
  function [22:0] lobe_rom;
    input [5:0] i;
    case (i)
      6'd0: lobe_rom = {9'd86, 9'd140, 5'd31}; 6'd1: lobe_rom = {9'd74, 9'd153, 5'd31}; 6'd2: lobe_rom = {9'd65, 9'd162, 5'd31}; 6'd3: lobe_rom = {9'd57, 9'd169, 5'd31};
      6'd4: lobe_rom = {9'd51, 9'd176, 5'd31}; 6'd5: lobe_rom = {9'd46, 9'd181, 5'd31}; 6'd6: lobe_rom = {9'd41, 9'd186, 5'd30}; 6'd7: lobe_rom = {9'd37, 9'd191, 5'd30};
      6'd8: lobe_rom = {9'd33, 9'd195, 5'd30}; 6'd9: lobe_rom = {9'd30, 9'd198, 5'd30}; 6'd10: lobe_rom = {9'd26, 9'd202, 5'd29}; 6'd11: lobe_rom = {9'd23, 9'd205, 5'd29};
      6'd12: lobe_rom = {9'd21, 9'd208, 5'd29}; 6'd13: lobe_rom = {9'd18, 9'd210, 5'd28}; 6'd14: lobe_rom = {9'd16, 9'd213, 5'd28}; 6'd15: lobe_rom = {9'd14, 9'd215, 5'd27};
      6'd16: lobe_rom = {9'd12, 9'd217, 5'd27}; 6'd17: lobe_rom = {9'd11, 9'd219, 5'd27}; 6'd18: lobe_rom = {9'd9, 9'd221, 5'd26}; 6'd19: lobe_rom = {9'd8, 9'd222, 5'd26};
      6'd20: lobe_rom = {9'd6, 9'd224, 5'd25}; 6'd21: lobe_rom = {9'd5, 9'd225, 5'd24}; 6'd22: lobe_rom = {9'd4, 9'd226, 5'd23}; 6'd23: lobe_rom = {9'd3, 9'd227, 5'd23};
      6'd24: lobe_rom = {9'd3, 9'd228, 5'd22}; 6'd25: lobe_rom = {9'd2, 9'd229, 5'd22}; 6'd26: lobe_rom = {9'd2, 9'd230, 5'd21}; 6'd27: lobe_rom = {9'd1, 9'd230, 5'd20};
      6'd28: lobe_rom = {9'd1, 9'd231, 5'd19}; 6'd29: lobe_rom = {9'd1, 9'd231, 5'd19}; 6'd30: lobe_rom = {9'd0, 9'd231, 5'd18}; 6'd31: lobe_rom = {9'd0, 9'd232, 5'd16};
      6'd32: lobe_rom = {9'd0, 9'd232, 5'd15}; 6'd33: lobe_rom = {9'd1, 9'd232, 5'd14}; 6'd34: lobe_rom = {9'd2, 9'd231, 5'd12}; 6'd35: lobe_rom = {9'd5, 9'd231, 5'd10};
      6'd36: lobe_rom = {9'd8, 9'd229, 5'd10}; 6'd37: lobe_rom = {9'd12, 9'd227, 5'd11}; 6'd38: lobe_rom = {9'd19, 9'd223, 5'd11}; 6'd39: lobe_rom = {9'd28, 9'd219, 5'd13};
      6'd40: lobe_rom = {9'd53, 9'd214, 5'd18}; 6'd41: lobe_rom = {9'd126, 9'd207, 5'd18}; 6'd42: lobe_rom = {9'd134, 9'd198, 5'd17};
      default: lobe_rom = {9'd1, 9'd0, 5'd0};
    endcase
  endfunction

  // -20 log10 sin(pi x/L), en pasos de 0.5 dB, indice |P|/8
  function [5:0] j_space_db;
    input [4:0] i;
    case (i)
      5'd0: j_space_db = 6'd0; 5'd1: j_space_db = 6'd0; 5'd2: j_space_db = 6'd0; 5'd3: j_space_db = 6'd0;
      5'd4: j_space_db = 6'd0; 5'd5: j_space_db = 6'd1; 5'd6: j_space_db = 6'd1; 5'd7: j_space_db = 6'd1;
      5'd8: j_space_db = 6'd2; 5'd9: j_space_db = 6'd2; 5'd10: j_space_db = 6'd2; 5'd11: j_space_db = 6'd3;
      5'd12: j_space_db = 6'd3; 5'd13: j_space_db = 6'd4; 5'd14: j_space_db = 6'd5; 5'd15: j_space_db = 6'd6;
      5'd16: j_space_db = 6'd6; 5'd17: j_space_db = 6'd7; 5'd18: j_space_db = 6'd8; 5'd19: j_space_db = 6'd10;
      5'd20: j_space_db = 6'd11; 5'd21: j_space_db = 6'd12; 5'd22: j_space_db = 6'd14; 5'd23: j_space_db = 6'd16;
      5'd24: j_space_db = 6'd18; 5'd25: j_space_db = 6'd20; 5'd26: j_space_db = 6'd23; 5'd27: j_space_db = 6'd26;
      5'd28: j_space_db = 6'd31; 5'd29: j_space_db = 6'd36; 5'd30: j_space_db = 6'd45; 5'd31: j_space_db = 6'd63;
      default: j_space_db = 6'd63;
    endcase
  endfunction

  // -20 log10 |cos(w t)|, en pasos de 0.5 dB
  function [5:0] j_time_db;
    input [4:0] i;
    case (i)
      5'd0: j_time_db = 6'd0; 5'd1: j_time_db = 6'd0; 5'd2: j_time_db = 6'd0; 5'd3: j_time_db = 6'd1;
      5'd4: j_time_db = 6'd1; 5'd5: j_time_db = 6'd2; 5'd6: j_time_db = 6'd3; 5'd7: j_time_db = 6'd4;
      5'd8: j_time_db = 6'd6; 5'd9: j_time_db = 6'd8; 5'd10: j_time_db = 6'd10; 5'd11: j_time_db = 6'd13;
      5'd12: j_time_db = 6'd17; 5'd13: j_time_db = 6'd21; 5'd14: j_time_db = 6'd28; 5'd15: j_time_db = 6'd40;
      5'd16: j_time_db = 6'd63; 5'd17: j_time_db = 6'd40; 5'd18: j_time_db = 6'd28; 5'd19: j_time_db = 6'd21;
      5'd20: j_time_db = 6'd17; 5'd21: j_time_db = 6'd13; 5'd22: j_time_db = 6'd10; 5'd23: j_time_db = 6'd8;
      5'd24: j_time_db = 6'd6; 5'd25: j_time_db = 6'd4; 5'd26: j_time_db = 6'd3; 5'd27: j_time_db = 6'd2;
      5'd28: j_time_db = 6'd1; 5'd29: j_time_db = 6'd1; 5'd30: j_time_db = 6'd0; 5'd31: j_time_db = 6'd0;
      default: j_time_db = 6'd63;
    endcase
  endfunction

  // Paleta: 0 = azul ... 31 = rojo
  function [11:0] heat;
    input [4:0] lv;
    reg [3:0] a;
    begin
      a = {lv[2:0], 1'b0};
      case (lv[4:3])
        2'd0: heat = {4'd3, a, 4'd15};
        2'd1: heat = {4'd0, 4'd15, 4'd14 - a};
        2'd2: heat = {a, 4'd15, 4'd0};
        default: heat = {4'd15, 4'd14 - a, 4'd0};
      endcase
    end
  endfunction

  // ---------------- Placa: pantalla -> coordenadas de placa ----------------
  // P a lo largo de L (parche en |P| < 256), Q a lo largo de W
  wire signed [13:0] xr = $signed({4'b0, pix_x}) - 14'sd320;
  wire signed [13:0] yd = $signed({4'b0, pix_y}) - 14'sd300;
  wire signed [13:0] P  = (xr <<< 2) + (yd <<< 1);
  wire signed [13:0] Q  = xr - (yd <<< 3);
  wire [13:0] aP = P[13] ? -P : P;
  wire [13:0] aQ = Q[13] ? -Q : Q;

  function on_board;
    input signed [13:0] p, q;
    on_board = (p > -14'sd652) && (p < 14'sd652) && (q > -14'sd609) && (q < 14'sd609);
  endfunction
  wire top  = on_board(P, Q);
  wire side = on_board(P - 14'sd12, Q + 14'sd48);   // canto del sustrato
  wire gnd  = on_board(P - 14'sd16, Q + 14'sd64);   // plano de tierra
  wire patch = (aP < 14'd256) && (aQ < 14'd331) && !((P < -14'sd91) && (aQ < 14'd44));
  wire feed  = (P < 14'sd0) && (aQ < 14'd27);

  wire [6:0] j_db  = (patch ? j_space_db(aP[7:3]) : 6'd6) + (avg ? 6'd0 : j_time_db(t[4:0]));
  wire [4:0] j_lev = 5'd31 - ((j_db > 7'd63) ? 5'd31 : j_db[5:1]);

  reg [11:0] board;
  always @* begin
    board = 12'haaa;                                  // fondo
    if (gnd)  board = 12'h333;
    if (side) board = 12'h62b;
    if (top)  board = (patch || feed) ? heat(j_lev) : 12'h31a;
  end

  // ---------------- Lobulo ----------------
  wire [9:0] dy = pix_y - 10'd170;
  wire [22:0] e = lobe_rom(dy[7:2]);
  wire [8:0] eL = e[22:14];
  wire [8:0] eR = e[13:5];
  wire signed [10:0] lx = $signed({1'b0, pix_x}) - 11'sd204;
  wire hit = !hide && (dy < 10'd172) && (lx >= $signed({2'b0, eL})) && (lx <= $signed({2'b0, eR}));

  // Sombreado: posicion lateral s en [-w, w]; mas oscuro a la derecha y hacia los bordes
  wire signed [11:0] s = $signed({lx, 1'b0}) - $signed({3'b0, eL}) - $signed({3'b0, eR});
  wire [11:0] as = s[11] ? -s : s;
  wire [11:0] w  = {3'b0, eR - eL};
  wire [1:0] d   = ({as[10:0], 1'b0} >= w) + (!s[11] && s != 12'sd0);
  wire outline   = (w >= 12'd3) && (as >= w - 12'd1);

  function [3:0] shade;
    input [3:0] c;
    input [1:0] k;
    shade = (k == 2'd0) ? c : (k == 2'd1) ? c - (c >> 2) : c - (c >> 1);
  endfunction
  wire [11:0] lc   = heat(e[4:0]);
  wire [11:0] lobe = {shade(lc[11:8], d), shade(lc[7:4], d), shade(lc[3:0], d)};
  wire [11:0] mix  = ((lobe >> 1) & 12'h777) + ((board >> 1) & 12'h777);
  wire [11:0] rgb  = !hit ? board : outline ? 12'h111 : glass ? mix : lobe;

  // ---------------- Tramado 2x2 a 2 bits por canal y salida registrada ----------------
  wire [1:0] th = {pix_x[0], 1'b0} ^ (pix_y[0] ? 2'd3 : 2'd0);
  function [1:0] q2;
    input [3:0] v;
    input [1:0] lim;
    q2 = (v[3:2] != 2'd3 && v[1:0] > lim) ? v[3:2] + 2'd1 : v[3:2];
  endfunction
  wire [1:0] R = video_active ? q2(rgb[11:8], th) : 2'd0;
  wire [1:0] G = video_active ? q2(rgb[7:4], th) : 2'd0;
  wire [1:0] B = video_active ? q2(rgb[3:0], th) : 2'd0;

  reg [7:0] uo_q;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) uo_q <= 8'b0;
    else uo_q <= {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uo_out = uo_q;

  wire _unused = &{1'b0, ena, uio_in, ui_in[7:3], t[5]};
endmodule

`default_nettype wire
