
// Copyright (c) 2014 Cornell University.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package BlockSync;

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import GetPut::*;
import ClientServer::*;

import Pipe::*;

interface BlockSync;
   interface PipeOut#(Bit#(66)) dataOut;
endinterface

typedef enum {LOCK_INIT, RESET_CNT, TEST_SH, GOOD_64, SLIP} State
deriving (Bits, Eq);

module mkBlockSync#(PipeOut#(Bit#(66)) blockSyncIn)(BlockSync);

   let verbose = False;

   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(State) curr_state <- mkReg(LOCK_INIT);
   Reg#(Bool) block_lock  <- mkReg(False);
   Reg#(Bool) slip_done   <- mkReg(False);
   Reg#(Bool) sh_valid    <- mkReg(False);
   Reg#(Bit#(32)) sh_cnt  <- mkReg(0);
   Reg#(Bit#(32)) sh_invalid_cnt <- mkReg(0);

   Reg#(Bit#(66)) rx_b1   <- mkReg(0);
   Reg#(Bit#(66)) rx_b2   <- mkReg(0);

   Reg#(Bit#(8)) offset   <- mkReg(0);
   FIFOF#(Bit#(66)) fifo_out <- mkFIFOF;
   FIFOF#(Bit#(66)) cfFifo <- mkFIFOF;

   rule cyc;
      cycle <= cycle + 1;
   endrule

   rule slip_data;// (curr_state != LOCK_INIT && curr_state != TEST_SH);
      Bit#(66) rx_b1_shifted;
      Bit#(66) rx_b2_shifted;
      Bit#(66) shifted;
      let v <- toGet(blockSyncIn).get;
      if(verbose) $display("%d: blocksync dataIn=%h", cycle, v);
      rx_b1_shifted = rx_b1 << offset;
      rx_b2_shifted = rx_b2 >> (66 - offset);
      shifted = rx_b1_shifted | rx_b2_shifted;

      rx_b1 <= v;
      rx_b2 <= rx_b1;

      cfFifo.enq(shifted);
      if(verbose) $display("%d: blocksync r1=%h r2=%h rs=%h", cycle, rx_b1_shifted, rx_b2_shifted, shifted);
   endrule

   (* fire_when_enabled, no_implicit_conditions *)
   rule state_lock_init (curr_state == LOCK_INIT);
      block_lock <= False;
      offset     <= 64;
      curr_state <= RESET_CNT;
      if(verbose) $display("%d: blocksync state_lock_init %d", cycle, curr_state);
   endrule

   rule state_reset_cnt (curr_state == RESET_CNT);
      let v <- toGet(cfFifo).get;
      sh_cnt <= 0;
      sh_invalid_cnt <= 0;
      slip_done <= False;
      curr_state <= TEST_SH;
      //if(verbose) $display("%d: state_reset_cnt", cycle);
   endrule

   // Optimized-away VALID_SH and INVALID_SH state
   rule state_test_sh (curr_state == TEST_SH);
      let v <- toGet(cfFifo).get;
      Bool sh_valid = unpack(v[0] ^ v[1]);
      if(verbose) $display("%d: test_sh %d %h", cycle, sh_cnt, v);

      // VALID_SH
      if (sh_valid) begin
         sh_cnt <= sh_cnt + 1;
         if (sh_cnt < 64) begin
            curr_state <= TEST_SH;
         end
         else if (sh_cnt == 64 && sh_invalid_cnt == 0) begin
            curr_state <= GOOD_64;
         end
         else if (sh_cnt == 64 && sh_invalid_cnt > 0) begin
            curr_state <= RESET_CNT;
         end
      end

      // INVALID_SH
      else if (!sh_valid) begin
         sh_cnt <= sh_cnt + 1;
         sh_invalid_cnt <= sh_invalid_cnt + 1;
         if (sh_cnt == 64 && sh_invalid_cnt < 16 && block_lock) begin
            curr_state <= RESET_CNT;
         end
         else if (sh_invalid_cnt == 16 || !block_lock) begin
            block_lock <= False;
            if (offset < 65) begin
               offset <= offset + 1;
            end
            else if (offset >= 65) begin
               offset <= 0;
            end
            curr_state <= RESET_CNT;
            if(verbose) $display("%d: blocksync state_slip %d offset=%d", cycle, curr_state, offset);
         end
         else if (sh_cnt < 64 && sh_invalid_cnt < 16 && block_lock) begin
            curr_state <= TEST_SH;
         end
      end

      if(verbose) $display("%d: blocksync state_test_sh %d, %d, %d", cycle, curr_state, pack(sh_valid), pack(block_lock));
   endrule

   rule state_good_64 (curr_state == GOOD_64);
      let v = cfFifo.first;
      cfFifo.deq;
      block_lock <= True;
      fifo_out.enq(v);
      if(verbose) $display("%d: blocksync state_good_64 %d, %d, enqueue %h", cycle, curr_state, pack(block_lock), v);
   endrule

   interface dataOut = toPipeOut(fifo_out);
endmodule
endpackage
