///////////////////////////////////////////
// SDC.sv
//
// Written: Ross Thompson September 22, 2021
// Modified: 
//
// Purpose: SDC interface to AHBLite BUS.
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, 
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
// is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT 
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///////////////////////////////////////////

`include "wally-config.vh"

`define SDCCLKDIV 8'd2

module SDC 
  (input  logic             HCLK, 
   input logic 		    HRESETn,
   input logic 		    HSELSDC,
   input logic [4:0] 	    HADDR,
   input logic 		    HWRITE,
   input logic 		    HREADY,
   input logic [1:0] 	    HTRANS,
   input logic [`XLEN-1:0]  HWDATA,
   output logic [`XLEN-1:0] HREADSDC,
   output logic 	    HRESPSDC, 
   output logic 	    HREADYSDC,

   //sd card interface
   // place the tristate drivers at the top.  this level
   // will use dedicated 1 direction ports.
   output logic 	    SDCCmdOut,
   input logic 		    SDCCmdIn,
   output logic 	    SDCCmdOE,
   input logic [3:0] 	    SDCDatIn,
   output logic 	    SDCCLK,

   // interrupt to PLIC
   output logic 	    SDCIntM);

  logic 		    InitTrans;
  logic 		    RegRead;
  logic 		    RegWrite;
  logic [4:0] 		    HADDRDelay;


  // Register outputs
  logic [7:0] 		    CLKDiv;
  logic [2:0] 		    Command;
  logic [63:9] 		    Address;
  

  logic 		    SDCDone;
  
  logic [2:0] 		    ErrorCode;
  logic 		    InvalidCommand;
  logic 		    Done;
  logic 		    Busy;

  logic 		    StartCLKDivUpdate;
  logic 		    CLKDivUpdateEn;
  logic 		    SDCCLKEN;
  logic 		    CLKGate;
  
  logic 		    SDCDataValid;
  logic [`XLEN-1:0] 	    SDCReadData;
  logic [`XLEN-1:0] 	    ReadData;
  

  // registers
  //| Offset | Name    | Size   | Purpose                                        |
  //|--------+---------+--------+------------------------------------------------|
  //|    0x0 | CLKDiv  |    4   | Divide HCLK to produce SDCLK                   |
  //|    0x4 | Status  |    4   | Provide status to software                     |
  //|    0x8 | Control |    4   | Send commands to SDC                           |
  //|    0xC | Size    |    4   | Size of data command (only 512 byte supported) |
  //|   0x10 | address |    8   | address of operation                           |
  //|   0x18 | data    | XLEN/8 | Data Bus interface                             |

  // Status contains
  // Status[0] 		    busy
  // Status[1] done
  // Status[2] invalid command
  // Status[5:3] error code
  
  // control contains 3 bit command
  // control[2:0]
  // 000 nop op
  // xx1 initialize
  // 010 Write  no implemented
  // 100 Read
  // 110 Atomic read/write not implemented

  // size is fixed to 512. Read only
  
  
  // Currently using a mailbox style interface.   Data is passed through the Data register (0x10)
  // The card will support 3 operations
  // 1. initialize
  // 2. read
  // 3. write
  // all read and write operations will occur on 512 bytes (4096 bits) of data
  // starting at the 512 byte aligned address in the address register  This register
  // is the byte address.

  // currently does not support writes

  assign InitTrans = HREADY & HSELSDC & (HTRANS != 2'b00);
  assign RegRead = InitTrans & ~HWRITE;
  // AHBLite Spec has write data 1 cycle after write command
  flopr #(1) RegWriteReg(HCLK, ~HRESETn, InitTrans & HWRITE, RegWrite);
  
  flopr #(5) HADDRReg(HCLK, ~HRESETn, HADDR, HADDRDelay);
  
  assign StartCLKDivUpdate = HADDRDelay == '0 & RegWrite;
  
  flopenl #(8) CLKDivReg(HCLK, ~HRESETn, CLKDivUpdateEn, HWDATA[7:0], `SDCCLKDIV, CLKDiv);

  // Control reg
  flopenl #(3) CommandReg(HCLK, ~HRESETn, (HADDRDelay == 'h8 & RegWrite) | (SDCDone), 
			   SDCDone ? '0 : HWDATA[2:0], '0, Command);

  generate
    if (`XLEN == 64) begin  
      flopenr #(64-9) AddressReg(HCLK, ~HRESETn, (HADDRDelay == 'h10 & RegWrite),
				 HWDATA[`XLEN-1:9], Address);
    end else begin
      flopenr #(32-9) AddressLowReg(HCLK, ~HRESETn, (HADDRDelay == 'h10 & RegWrite),
				    HWDATA[`XLEN-1:9], Address[31:9]);
      flopenr #(32) AddressHighReg(HCLK, ~HRESETn, (HADDRDelay == 'h14 & RegWrite),
				   HWDATA, Address[63:32]);
    end
  endgenerate
  
  flopen #(`XLEN) DataReg(HCLK, (HADDRDelay == 'h18 & RegWrite) | (SDCDataValid),
			  SDCDataValid ? SDCReadData : HWDATA, ReadData);

  generate
    if(`XLEN == 64) begin
      always_comb
	case(HADDRDelay[4:0]) 
	  'h0: HREADSDC = {56'b0, CLKDiv};
	  'h4: HREADSDC = {58'b0, ErrorCode, InvalidCommand, Done, Busy};
	  'h8: HREADSDC = {61'b0, Command};
	  'hC: HREADSDC = 'h200;
	  'h10: HREADSDC = {Address, 9'b0};
	  'h18: HREADSDC = ReadData;
	  default: HREADSDC = {56'b0, CLKDiv};
	endcase
    end  else begin
      always_comb
	case(HADDRDelay[4:0]) 
	  'h0: HREADSDC = {24'b0, CLKDiv};
	  'h4: HREADSDC = {26'b0, ErrorCode, InvalidCommand, Done, Busy};
	  'h8: HREADSDC = {29'b0, Command};
	  'hC: HREADSDC = 'h200;
	  'h10: HREADSDC = {Address[31:9], 9'b0};
	  'h14: HREADSDC = Address[63:32];	  
	  'h18: HREADSDC = ReadData[31:0];
	  default: HREADSDC = {24'b0, CLKDiv};
	endcase
    end
  endgenerate

  typedef enum {STATE_READY,

		// clock update states
		STATE_CLK_DIV1,
		STATE_CLK_DIV2,
		STATE_CLK_DIV3,
		STATE_CLK_DIV4,

		// restart SDC
		STATE_RESTART,

		// SDC operation
		STATE_PROCESS_CMD
		} statetype;


  statetype CurrState, NextState;
  
  always_ff @(posedge HCLK, negedge HRESETn)
    if (~HRESETn)    CurrState <=  STATE_READY;
    else CurrState <= NextState;

  always_comb begin
    CLKDivUpdateEn = 1'b0;
    HREADYSDC = 1'b0;
    SDCCLKEN = 1'b1;
    case (CurrState)

      STATE_READY : begin
	if (StartCLKDivUpdate)begin
	  NextState = STATE_CLK_DIV1;
	  HREADYSDC = 1'b0;
/* -----\/----- EXCLUDED -----\/-----
	end else if () begin
 -----/\----- EXCLUDED -----/\----- */
	  
	end else begin
	  NextState = STATE_READY;
	  HREADYSDC = 1'b1;
	end
      end
      STATE_CLK_DIV1: begin
	NextState = STATE_CLK_DIV2;
	SDCCLKEN = 1'b0;
      end
      STATE_CLK_DIV2: begin
	NextState = STATE_CLK_DIV3;
	CLKDivUpdateEn = 1'b1;
	SDCCLKEN = 1'b0;
      end
      STATE_CLK_DIV3: begin
	NextState = STATE_CLK_DIV4;
	SDCCLKEN = 1'b0;
      end
      STATE_CLK_DIV4: begin
	NextState = STATE_READY;
      end
    endcase
  end

  // clock generation divider

  clockgater clockgater(.E(SDCCLKEN),
			.SE(1'b0),
			.CLK(HCLK),
			.ECLK(CLKGate));


  clkdivider #(8) clkdivider(.i_COUNT_IN_MAX(CLKDiv),
			     .i_EN(CLKDiv != 'b1),
			     .i_CLK(CLKGate),
			     .i_RST(~HRESETn),
			     .o_CLK(SDCCLK));
  
  
  
endmodule
	    
