
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

package EthPorts;

import Clocks::*;
import Vector::*;
import Connectable::*;

import Ethernet::*;
import EthMac::*;
import EthPhy::*;
import EthPktCtrl::*;
import Avalon2ClientServer::*;
import AvalonStreaming::*;

`ifdef NUMBER_OF_10G_PORTS
typedef `NUMBER_OF_10G_PORTS NumPorts;
`else
typedef 4 NumPorts;
`endif

(* always_ready, always_enabled *)
interface EthPortIfc;
   interface AvalonSlaveIfc#(24) avs;
   interface Vector#(NumPorts, SerialIfc) serial;
endinterface

(* synthesize *)
(* clock_family = "default_clock, clk_156_25" *)
module mkEthPorts#(Clock clk_50, Clock clk_156_25, Clock clk_644, Reset rst_50, Reset rst_156_25)(EthPortIfc);
   Vector#(NumPorts, EthPktCtrlIfc) pktctrls <- replicateM(mkEthPktCtrl(clk_156_25, rst_156_25, clocked_by clk_156_25, reset_by rst_156_25));
   EthMacIfc#(NumPorts) macs <- mkEthMac(clk_50, rst_50, clk_156_25, rst_156_25, clocked_by clk_156_25, reset_by rst_156_25);
   EthPhyIfc#(NumPorts) phys <- mkEthPhy(clk_50, rst_50, clk_156_25, rst_156_25, clk_644, clocked_by clk_156_25, reset_by rst_156_25);

   for (Integer i=0; i<valueOf(NumPorts); i=i+1) begin
      mkConnection(pktctrls[i].aso, macs.avalon[i].asi);
      mkConnection(macs.avalon[i].aso, pktctrls[i].asi);
      mkConnection(macs.xgmii[i], phys.xgmii[i]);
   end

   interface serial = phys.serial;
   interface avs = pktctrls[0].avs;

endmodule: mkEthPorts
endpackage: EthPorts