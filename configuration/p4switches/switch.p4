/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

#define REGISTER_SIZE 8192
#define TIMESTAMP_WIDTH 48
#define ID_WIDTH 16
#define FLOWLET_TIMEOUT 48w200000 //200ms (standard value reference from the exercise)

// LFA ADD
#define N_PREFS 1024
#define PORT_WIDTH 32
#define N_PORTS 512

// Bandwidth
#define BW 12

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

// IP header definition
header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<6>    dscp; //This is the part of the TOS field we will use  
    bit<2>    ecn;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

// TCP header definition
header tcp_t{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<1>  cwr;
    bit<1>  ece;
    bit<1>  urg;
    bit<1>  ack;
    bit<1>  psh;
    bit<1>  rst;
    bit<1>  syn;
    bit<1>  fin;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

// UDP header definition
header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}

// BFD header definition
header bfd_t {
    bit<3> version;
    bit<5> diag;
    bit<2> sta;
    bit<6> flags;
    bit<8> detect_mult;
    bit<8> len;
    bit<32> my_discriminator;
    bit<32> your_discriminator;
    bit<32> min_tx_interval;
    bit<32> min_rx_interval;
    bit<32> echo_rx_interval;
}


struct metadata {
    
    // Metadata for Multipath hashing 
    bit<14> mp_hash;
    bit<14> mp_group_id;

    // Metadata for flowlet switching
    bit<48> flowlet_last_stamp;
    bit<48> flowlet_time_diff;

    bit<13> flowlet_register_index;
    bit<16> flowlet_id;


    // Metadata for LFA
    bit<1> linkState;
    bit<32> nextHop;
    bit<32> index;
    bit<32> index_bw;

    // Metadata for bandwidth 
    bit<1> Bandwidth;

}

struct headers {
    ethernet_t  ethernet;
    ipv4_t 	    ipv4;
    tcp_t	    tcp;
    udp_t       udp;
    bfd_t       bfd;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    // parse ethernet header
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType){
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    // parse ipv4 header
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol){
            17 : parse_udp;
            default: accept;
        }
    }

    // parse udp header as hosts send UDP flows
    state parse_udp {
        packet.extract(hdr.udp);
        transition select(hdr.udp.dstPort){
            // bfd packets arrive at udp port 3784
            3784: parse_bfd;
            default: accept;
        }
    }

    // parse the bfd header
    state parse_bfd {
        packet.extract(hdr.bfd);
        transition accept;
    }

}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

                      
    // Registers to keep track of flowlets
    register<bit<ID_WIDTH>>(REGISTER_SIZE) flowlet_to_id;
    register<bit<TIMESTAMP_WIDTH>>(REGISTER_SIZE) flowlet_time_stamp;
  

    action drop() {
        mark_to_drop(standard_metadata);
    }

    // Register to look up the port of the default next hop
    register<bit<PORT_WIDTH>>(N_PREFS) primaryNH;
    register<bit<PORT_WIDTH>>(N_PREFS) alternativeNH; 

    // Register containing link states. 0: No Problems. 1: Link failure.
    // This register is updated by controller.py.
    register<bit<1>>(N_PORTS) linkState;

    // Register for reading bandwidth 
    register<bit<1>>(BW) Bandwidth;

    // Queries LinkState
    action query_nextLink(bit<32>  index){ 
        meta.index = index;
        // Read primary next hop and write result into meta.nextHop. 
        primaryNH.read(meta.nextHop,  meta.index);
        
        // Read linkState of controller-chosen next hop.
        linkState.read(meta.linkState, meta.nextHop);
    }

    // Action to read bandwidth (bandwidth refers to incoming datarate of the flow)
    action read_bandwidth(bit<32>  index_bw){
        meta.index_bw = index_bw;
        // Read value and write the data into the meta.Bandwidth
        Bandwidth.read(meta.Bandwidth, meta.index_bw);
    }

    // Called when Link is down to find LFA
    action read_alternativePort(){ 
        // Read alternative next hop into metadata
        alternativeNH.read(meta.nextHop, meta.index);
    }

    // This updates the destination when the LFA gets triggered
    action rewriteMac(macAddr_t dstAddr){ 
	    hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        standard_metadata.egress_spec = (bit<9>) meta.nextHop;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
	}

    // Match destination address to index
    table dst_index { 
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            query_nextLink;
            drop;
        }
        size = 512;
        default_action = drop;
    }

    // This matches the LFA to an address
    table rewrite_mac { 
        key = {
             meta.nextHop: exact;
        }
        actions = {
            rewriteMac;
            drop;
        }
        size = 512;
        default_action = drop;
    }

    // Action to read flowlet registers
    action read_flowlet_registers(){
        // compute the register index
        hash(meta.flowlet_register_index, HashAlgorithm.crc16,
            (bit<16>)0,
            { hdr.ipv4.srcAddr,
            hdr.ipv4.dstAddr,
            hdr.udp.srcPort,
            hdr.udp.dstPort,
            hdr.ipv4.protocol},
            (bit<14>)8192);

         // Read the previous time stamp
        flowlet_time_stamp.read(meta.flowlet_last_stamp, (bit<32>)meta.flowlet_register_index);

        // Read the previous flowlet id
        flowlet_to_id.read(meta.flowlet_id, (bit<32>)meta.flowlet_register_index);

        // Update the timestamp
        flowlet_time_stamp.write((bit<32>)meta.flowlet_register_index, standard_metadata.ingress_global_timestamp);
    }

    // Action to update the flowlet id
    action update_flowlet_id(){
        bit<32> random_t;
        random(random_t, (bit<32>)0, (bit<32>)65000);
        meta.flowlet_id = (bit<16>)random_t;
        flowlet_to_id.write((bit<32>)meta.flowlet_register_index, (bit<16>)meta.flowlet_id);
    }


    // Action to compute the Multipath group for next hop
    action mp_group(bit<14> mp_group_id, bit<16> num_nhops){
        hash(meta.mp_hash,
            HashAlgorithm.crc16,
            (bit<1>)0,
            {hdr.ipv4.srcAddr,
            hdr.ipv4.dstAddr,
            hdr.udp.srcPort,
            hdr.udp.dstPort,
            hdr.ipv4.protocol,
            meta.flowlet_id},
            num_nhops);

            meta.mp_group_id = mp_group_id;
    }

    // Action for routing the next hop (Multipath) 
    action set_nhop(macAddr_t dstAddr, egressSpec_t port) {
            // While it does the same thing as rewrite_mac
            // it is for multipathing, not LFAs
            hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
            hdr.ethernet.dstAddr = dstAddr;
            standard_metadata.egress_spec = port;
            hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    // Matches mp_group_id and mp_hash to the chosen next_hop
    table mp_group_to_nhop {
        key = {
            meta.mp_group_id: exact;
            meta.mp_hash: exact;
        }
        actions = {
            drop;
            set_nhop;
        }
        size = 1024;
    }

    // Matches on the dstAddrs and sets the next hop
    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            set_nhop;
            mp_group;
            drop;
        }
        size = 1024;
        default_action = drop;
    }

    action l2_forward_action(egressSpec_t port) {
        standard_metadata.egress_spec = port;
    }

    action broadcast() {
        standard_metadata.mcast_grp =  1;
    }

    table l2_forward {
        key = {
            hdr.ethernet.dstAddr: exact;
        }
        actions = {
            l2_forward_action;
            broadcast;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = drop();
    }



    apply {

        // Apply basic L2 forwarding
        l2_forward.apply(); 

        // Check if there is a valid ipv4 header
        if (hdr.ipv4.isValid()){
            

            // This is used for link failure detection.
            // If the packet is a BFD packet, send it to the controller
            if(hdr.bfd.isValid()){
                // Modify the BFD.flags so we can determine on the controller
                // if a packet has actually already travelled the link or 
                // is being sniffed where it was sent from
                hdr.bfd.flags = (bit<6>)1;
                clone(CloneType.I2E, 100);
            } 
            else {
                // We use Multipath for Silver and Bronze traffic.
                // In our case "Multipath", splits over all paths not just equicost paths, which is inspired by ECMP.
          
                // Split at per packet basis for bronze and silver traffic over all the available egress paths. This is 
                // because bronze and silver need larger datarates (12Mbps and 6Mbps) compared to the bandwidths of the egress links
                // and we want maximize link utilization. 
                // Hence, we extended the flowlet switching to near packet switching (inter packet gap <  flowlet timeout) 
                // for bronze and silver traffic within a flow as packet reordering does not matter for our network.
            
                // TOS = 32 corresponds to DSCP = 8 (bronze traffic)
                // TOS = 64 corresponds to DSCP = 16 (silver traffic)

                // A more generic solution exists if the we don't check using the TOS field in the P4 code, but rather use 
                // the traffic matrix provided by the controlller to read the incoming datarates of the flows. If the incoming 
                // flow has a datarate of  > 4 Mbps which is greater than the egress link bandwidth, we split the traffic all the 
                // egress paths. The bandwidth register keeps a track of this and when set to 1, it splits the traffic.
                // This is an alternative solution.
                    
                // read_bandwidth( 0);
                // if (meta.Bandwidth == 1){
                if(hdr.ipv4.dscp == 8  || hdr.ipv4.dscp == 16){

                    @atomic {
                        read_flowlet_registers();
                        // Calculate the inter packet arrival time
                        meta.flowlet_time_diff = standard_metadata.ingress_global_timestamp - meta.flowlet_last_stamp;

                        // Check if inter-packet gap is < the timeout (large enough timeout).
                        // if this condition is true, the flowlet_id is updated for every packet.
                        // this recalculates the hash and puts each packet on a new link.
                        if (meta.flowlet_time_diff < FLOWLET_TIMEOUT){
                            update_flowlet_id();
                        }
                    }
                    
                    // Apply the Multipath group next hop for bronze and silver( per packet)
                    switch (ipv4_lpm.apply().action_run){
                        mp_group: {
                            mp_group_to_nhop.apply();
                        }
                    }
                }

                else {
                    // Now we take the case of TOS = 128 (gold)

                    // For gold traffic, we route by the shortest path,
                    // as the data rate (1M) is less than the bandwidth of every
                    // possible link
                    // We configure an LFA just for gold traffic as it is not split and
                    // there are backup links available for gold traffic as a result.

                    // This checks if the link to the nextHop is up
    	 	        dst_index.apply(); 

                    // If the link is down, use the LFA as the next hop
                	if (meta.linkState > 0){
                    	read_alternativePort();
                    }	

                	// This table sends the gold traffic to it's next hop,
                    // regardless whether it's primary next hop or the LFA
                    rewrite_mac.apply(); 
                } 
            } 
        }
    }
}       

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
     apply {
	// Checksum to be updated as changes made in the IP header
	update_checksum(
            hdr.ipv4.isValid(),
            { hdr.ipv4.version,
              hdr.ipv4.ihl,
              hdr.ipv4.dscp,
              hdr.ipv4.ecn,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);

    }
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {

        // Parsed headers have to be added again into the packet.
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);

        // Only emited if valid
        packet.emit(hdr.udp);
        packet.emit(hdr.bfd);

    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

//switch architecture
V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
