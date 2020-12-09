/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

#define REGISTER_SIZE 8192
#define TIMESTAMP_WIDTH 48
#define ID_WIDTH 16
#define FLOWLET_TIMEOUT 48w200000 //200ms

//LFA ADD
#define N_PREFS 1024
#define PORT_WIDTH 32
#define N_PORTS 512

//Bandwidth
<<<<<<< HEAD
#define BW 12
=======
#define BW 1
>>>>>>> 162ea60ecaeffaf3403e0fc0a19b152731f3f8d2

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

//IP header definition
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

//TCP header definition
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

//UDP header definition

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}

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
    
    // Metadata for ECMP hashing 
    bit<14> ecmp_hash;
    bit<14> ecmp_group_id;

    //Metadata for flowlet switching
    bit<48> flowlet_last_stamp;
    bit<48> flowlet_time_diff;

    bit<13> flowlet_register_index;
    bit<16> flowlet_id;


    //Metadata for LFA
    bit<1> linkState;
    bit<32> nextHop;
    bit<32> index;

    //Metadata for bandwidth 
    bit<1> Bandwidth;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t 	 ipv4;
    tcp_t	 tcp;
    udp_t        udp;
    bfd_t bfd;
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

    //parse ethernet header
    state parse_ethernet {

        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType){
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    //parse ipv4 header
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol){
            17 : parse_udp;
            default: accept;
        }
    }

    //parse udp header as hosts send UDP flows
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

                      
    register<bit<ID_WIDTH>>(REGISTER_SIZE) flowlet_to_id;
    register<bit<TIMESTAMP_WIDTH>>(REGISTER_SIZE) flowlet_time_stamp;
  

    action drop() {
        mark_to_drop(standard_metadata);
    }

    //********************** ADD FOR LFA********************
    // Register to look up the port of the default next hop.
    register<bit<PORT_WIDTH>>(N_PREFS) primaryNH;
    register<bit<PORT_WIDTH>>(N_PREFS) alternativeNH; 

    // Register containing link states. 0: No Problems. 1: Link failure.
    // This register is updated by CLI.py, you only need to read from it.
    register<bit<1>>(N_PORTS) linkState;

    // Register for reading bandwidth 
<<<<<<< HEAD
    register<bit<1>>(BW) Bandwidth;
=======
    register<bit<1>>(N_PORTS) Bandwidth;
>>>>>>> 162ea60ecaeffaf3403e0fc0a19b152731f3f8d2

    action query_nextLink(bit<32>  index){ //Queries LinkState
        meta.index = index;
        // Read primary next hop and write result into meta.nextHop. This is not used for the actual nextHop, it is used just to query the Link. 
        primaryNH.read(meta.nextHop,  meta.index);
        
        //Read linkState of default next hop.
        linkState.read(meta.linkState, meta.nextHop);
    }

    // Action to read bandwidth
    action read_bandwidth(bit<32>  index){

        meta.index = index;
        // Read value and write the data into the meta.Bandwidth
        Bandwidth.read(meta.Bandwidth, meta.index);
    }
    
    action read_alternativePort(){ //Called when Link is down to find LFA
        //Read alternative next hop into metadata
        alternativeNH.read(meta.nextHop, meta.index);
    }

    action rewriteMac(macAddr_t dstAddr){ //This updates the destination when the LFA gets triggered
	    hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        standard_metadata.egress_spec = (bit<9>) meta.nextHop;
         //decrease ttl by 1
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
	}

    table dst_index { //Match destination addres to index
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

    table rewrite_mac { //this matches the LFA to an address
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

    
    //********************** ADD FOR LFA********************

    
    // Action to read flowlet registers
    action read_flowlet_registers(){

        //compute the register index
        hash(meta.flowlet_register_index, HashAlgorithm.crc16,
            (bit<16>)0,
            { hdr.ipv4.srcAddr,
            hdr.ipv4.dstAddr,
            hdr.udp.srcPort,
            hdr.udp.dstPort,
            hdr.ipv4.protocol},
            (bit<14>)8192);

         //Read the previous time stamp
        flowlet_time_stamp.read(meta.flowlet_last_stamp, (bit<32>)meta.flowlet_register_index);

        //Read the previous flowlet id
        flowlet_to_id.read(meta.flowlet_id, (bit<32>)meta.flowlet_register_index);

        //Update the timestamp
        flowlet_time_stamp.write((bit<32>)meta.flowlet_register_index, standard_metadata.ingress_global_timestamp);
    }

    action update_flowlet_id(){
        bit<32> random_t;
        random(random_t, (bit<32>)0, (bit<32>)65000);
        meta.flowlet_id = (bit<16>)random_t;
        flowlet_to_id.write((bit<32>)meta.flowlet_register_index, (bit<16>)meta.flowlet_id);
    }


    //action to compute the ecmp group for next hop
    action ecmp_group(bit<14> ecmp_group_id, bit<16> num_nhops){
        hash(meta.ecmp_hash,
            HashAlgorithm.crc16,
            (bit<1>)0,
            {hdr.ipv4.srcAddr,
            hdr.ipv4.dstAddr,
            hdr.udp.srcPort,
            hdr.udp.dstPort,
            hdr.ipv4.protocol,
            meta.flowlet_id},
            num_nhops);

            meta.ecmp_group_id = ecmp_group_id;
    }

    //action for routing the next hop (ECMP) 
    action set_nhop(macAddr_t dstAddr, egressSpec_t port) {

            //set the src mac address as the previous dst
            hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;

            //set the destination mac address 
            hdr.ethernet.dstAddr = dstAddr;

            
            //set the output port 
            standard_metadata.egress_spec = port;
        

            //decrease ttl by 1
            hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ecmp_group_to_nhop {
        key = {
            meta.ecmp_group_id: exact;
            meta.ecmp_hash: exact;
        }
        actions = {
            drop;
            set_nhop;
        }
        size = 1024;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            set_nhop;
            ecmp_group;
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

        l2_forward.apply(); 

        if (hdr.ipv4.isValid()){

            // if the packet is a bsd packet, send it to the controller
            if(hdr.bfd.isValid()){
                clone(CloneType.I2E, 100);
            }


            else {


            // If Links are up, then ECMP is triggerd. In our case "ECMP", splits over all paths not just equicost paths.
		    // This isn't true ECMP but the idea is derived from ECMP to work for our speficic network

            
                    // Split at per packet basis for bronze and silver traffic over all the cost egress paths. This is 
                    // because bronze and silver needs larger datarate (12M and 6M) compared to the bandwidth of the egress links
                    // and we want to utilise all the links. Our idea is to split bronze and silver traffic over all the links.
                    // Hence, we extended the flowlet switching to near packet switching (inter packet gap <  flowlet timeout) 
                    //for bronze and silver traffic within a flow as packet reordering does not matter for our network.
            
                    // TOS = 32 corresponds to DSCP = 8 (bronze traffic)
                    // TOS = 64 corresponds to DSCP = 16 (silver traffic)
<<<<<<< HEAD

                    // A more generic solution exists if the we don't check using the TOS field in the P4 code, rather use 
                    // the traffic matrix to read the incoming datarates of the flows. If the incoming flow has a datarate
                    // of  > 4 Mbps which is greater than the egress link bandwidth, we split the traffic all all the 
                    //egress paths. The bandwidth register keeps a track of this and when set to 1, it splits the traffic.
                    
                    read_bandwidth( 0);
=======
>>>>>>> 162ea60ecaeffaf3403e0fc0a19b152731f3f8d2
                    if (meta.Bandwidth == 1){
                    //if(hdr.ipv4.dscp == 8  || hdr.ipv4.dscp == 16){

                        @atomic {
                            read_flowlet_registers();
                            meta.flowlet_time_diff = standard_metadata.ingress_global_timestamp - meta.flowlet_last_stamp;

                            //check if inter-packet gap is < the timeout
                            if (meta.flowlet_time_diff < FLOWLET_TIMEOUT){
                                update_flowlet_id();
                            }
                        }
                    
                        //Apply the ecmp group next hop for bronze and silver( per packet)
                        switch (ipv4_lpm.apply().action_run){
                            ecmp_group: {
                                ecmp_group_to_nhop.apply();
                            }
                        }
                    }

                    else {
			
			// Now we take the case of TOS = 128 (gold)
			//********************** ADD FOR LFA********************	
			
			// For gold traffic, we only split per flow for different paths 
			// as the data rate (1M) is less than the bandwidth of every
			// possible link

			// We configure an LFA just for gold traffic as it is not split
			// there are backup links available for gold traffic

            // If we use the second approach (splitting based on data-rate, not TOS),
            // that we don't split the traffic for data rate <= 4 Mbps, 
            // we put all the traffic on one link and if there is a failure, use an LFA.
			
 
		 	dst_index.apply(); //This checks if the link to the nextHop is up

                	if (meta.linkState == 1){

                     	//If the link is down, trigger the LFA code

                    	read_alternativePort();
                    	rewrite_mac.apply();
                        }	

                	else {

                        // Apply the "our ecmp"  per flow for gold (TOS = 128) 
		                // traffic classes
                        switch (ipv4_lpm.apply().action_run){
                            ecmp_group: {
                                ecmp_group_to_nhop.apply();
                            }
                        }
                    }
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
	//Checksum to be updated as changes made in the IP header
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

        //parsed headers have to be added again into the packet.
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);

        //Only emited if valid
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
