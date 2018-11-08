/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

// #define ENABLE_DEBUG_ETHERNET
// #define ENABLE_DEBUG_ARP
//#define ENABLE_DEBUG_IP
//#define ENABLE_DEBUG_TCP
// #define ENABLE_DEBUG_UDP
// #define ENABLE_DEBUG_META



// #define ENABLE_DEBUG_ETHERNET_EGRESS
// #define ENABLE_DEBUG_ARP_EGRESS
// #define ENABLE_DEBUG_IP_EGRESS
// #define ENABLE_DEBUG_TCP_EGRESS
// #define ENABLE_DEBUG_UDP_EGRESS
// #define ENABLE_DEBUG_META_EGRESS



const bit<16> UDP_LEN = 16w8;
const bit<16> IPV4_LEN = 16w20;


// ----------------    ETHERNET TYPES    --------------------
const bit<16> TYPE_IPV4 = 0x0800;
//ARP
const bit<16> TYPE_ARP = 0x0806;
//===========================================================


// ------------------ IPv4 PROTOCOL TYPES -------------------
//ICMP
const bit<8> IP_PROTO_ICMP = 0x01;
//TCP
const bit<8> IP_PROTO_TCP = 0x06;
//UDP
const bit<8> IP_PROTO_UDP = 0x11;
//===========================================================

// ARP RELATED CONST VARS
const bit<16> ARP_HTYPE = 0x0001; //Ethernet Hardware type is 1
const bit<16> ARP_PTYPE = TYPE_IPV4; //Protocol used for ARP is IPV4
const bit<8>  ARP_HLEN  = 6; //Ethernet address size is 6 bytes
const bit<8>  ARP_PLEN  = 4; //IP address size is 4 bytes
const bit<16> ARP_REQ = 1; //Operation 1 is request
const bit<16> ARP_REPLY = 2; //Operation 2 is reply

/* FURTHER ARP HEADER FIELDS TO BE AWARE OF
 * bit<48> ARP_SRC_MAC (requester's MAC)
 * bit<32> ARP_SRC_IP  (tell DST_MAC to this IP)
 * bit<48> ARP_DST_MAC (Looking for this MAC)
 * bit<32> ARP_DST_IP  (who has this IP)
 */


/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/
typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

//payload specific variables
typedef bit<16> tcp_payload_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
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

header arp_t {
  bit<16>   h_type;
  bit<16>   p_type;
  bit<8>    h_len;
  bit<8>    p_len;
  bit<16>   op_code;
  macAddr_t src_mac;
  ip4Addr_t src_ip;
  macAddr_t dst_mac;
  ip4Addr_t dst_ip;
  }

header tcp_t2
{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset; //i.e., TCP length in 32-bit words -> [5,15]
    bit<4>  flags_1;
    bit<4>  flags_2;
    bit<4>  flags_3;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
    bit<96> options;
}

header udp_t
{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> len;
    bit<16> checksum;
    bit<120> payload;
}




// metadata for TCP (mostly, for TCP checksum recomputation if needed)
struct tcp_metadata_t
{
    bit<16> full_length; //ipv4.totalLen - 20
    bit<16> full_length_in_bytes;
    bit<16> header_length;
    bit<16> header_length_in_bytes;
    bit<16> payload_length;
    bit<16> payload_length_in_bytes;
}

struct udp_metadata_t
{
   //will be calculated when UDP payload needs to be changed
   //Subtracting hdr.udp.len - 8bytes
    bit<16> udp_payload_length;
}


struct metadata {
    /* empty */
    udp_metadata_t udp_metadata;
    tcp_metadata_t tcp_metadata;
}



struct headers {
    ethernet_t   ethernet;
    arp_t        arp;
    ipv4_t       ipv4;
    tcp_t2        tcp;
    udp_t        udp;

}

// Define additional error values, one of them for packets with
// incorrect IPv4 header checksums.
error {
    UnhandledIPv4Options,
    IPv4IncorrectVersion,
    BadIPv4HeaderChecksum
}

// extern ExternIncrease;
//{
//   ExternIncrease(bit<8> attribute_example);
//   void increase();
//}


/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata)
{

    //Checksum16() ck;  // instantiate checksum unit
    state start
    {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType)
        {
            TYPE_ARP: parse_arp;
            TYPE_IPV4: parse_ipv4;
        }
    }

    state parse_arp
    {
        packet.extract(hdr.arp);
        transition select(hdr.arp.op_code)
        {
            ARP_REQ: accept;
        }
    }

    state parse_ipv4
    {
        packet.extract(hdr.ipv4);
        verify(hdr.ipv4.version == 4, error.IPv4IncorrectVersion);
        verify(hdr.ipv4.ihl == 5, error.UnhandledIPv4Options);
        transition select(hdr.ipv4.protocol)
        {
            IP_PROTO_TCP: parse_tcp;
            IP_PROTO_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_tcp
    {
        packet.extract(hdr.tcp);
        meta.tcp_metadata.full_length = (hdr.ipv4.totalLen - IPV4_LEN) * 8;
        meta.tcp_metadata.header_length = (((bit<16>)hdr.tcp.dataOffset) << 5);
        meta.tcp_metadata.payload_length = meta.tcp_metadata.full_length - meta.tcp_metadata.header_length;

        meta.tcp_metadata.full_length_in_bytes =  (hdr.ipv4.totalLen - IPV4_LEN);
        meta.tcp_metadata.header_length_in_bytes = (bit<16>)hdr.tcp.dataOffset << 2;
        meta.tcp_metadata.payload_length_in_bytes = (hdr.ipv4.totalLen - IPV4_LEN) - ((bit<16>)hdr.tcp.dataOffset << 2);
        transition accept;
    }

    state parse_udp
    {
        packet.extract(hdr.udp);
        meta.udp_metadata.udp_payload_length = hdr.udp.len - UDP_LEN;
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
***********  D E B U G - I N G R E S S   P R O C E S S I N G   ***********
*************************************************************************/
// #ifdef ENABLE_DEBUG_ETHERNET
#if defined(ENABLE_DEBUG_IP_ETHERNET) || defined(ENABLE_DEBUG_ETHERNET_EGRESS)
control ethernet_debug(in headers hdr,
                               inout metadata meta,
                               in standard_metadata_t standard_metadata)
{
    //define debug table
    table ethernet_debug_table
    {
        //define keys to match/debug - comment/uncomment to see in log
        key =
        {
            standard_metadata.ingress_port : exact;
            hdr.ethernet.etherType:    exact;
            hdr.ethernet.srcAddr:      exact;
            hdr.ethernet.dstAddr:      exact;
        }

        // we define no action here, as this table has only debug purposes
        actions = { NoAction; }
        // define the default noaction for each match
        const default_action = NoAction();
    }

    //what to apply for this debug ingress processing
    apply
    {
        ethernet_debug_table.apply();
    }

}
#endif //ENABLE_DEBUG_ETHERNET || ENABLE_DEBUG_ETHERNET_EGRESS

#if defined(ENABLE_DEBUG_ARP) || defined(ENABLE_DEBUG_ARP_EGRESS)
control arp_debug(in headers hdr,
                          inout metadata meta,
                          in standard_metadata_t standard_metadata)
{
    //define debug table
    table arp_debug_table
    {
        //define keys to match/debug - comment/uncomment to see in log
        key =
        {
            standard_metadata.ingress_port : exact;
            hdr.arp.h_type:    exact;
            hdr.arp.p_type:    exact;
            hdr.arp.h_len:     exact;
            hdr.arp.p_type:    exact;
            hdr.arp.op_code:   exact;
            hdr.arp.src_mac:   exact;
            hdr.arp.src_ip:    exact;
            hdr.arp.dst_mac:   exact;
            hdr.arp.dst_ip:    exact;

        }

        // we define no action here, as this table has only debug purposes
        actions = { NoAction; }
        // define the default noaction for each match
        const default_action = NoAction();
    }

    //what to apply for this debug ingress processing
    apply
    {
        arp_debug_table.apply();
    }

}
#endif //ENABLE_DEBUG_ARP

#if defined(ENABLE_DEBUG_IP) || defined(ENABLE_DEBUG_IP_EGRESS)
control ip_debug(in headers hdr,
                         inout metadata meta,
                         in standard_metadata_t standard_metadata)
{
    //define debug table
    table ip_debug_table
    {
        //define keys to match/debug - comment/uncomment to see in log
        key =
        {
            standard_metadata.ingress_port : exact;
            hdr.ipv4.version:           exact;
            hdr.ipv4.ihl:               exact;
            hdr.ipv4.diffserv:          exact;
            hdr.ipv4.totalLen:          exact;
            hdr.ipv4.identification:    exact;
            hdr.ipv4.flags:             exact;
            hdr.ipv4.fragOffset:        exact;
            hdr.ipv4.ttl:               exact;
            hdr.ipv4.protocol:          exact;
            hdr.ipv4.hdrChecksum:       exact;
            hdr.ipv4.srcAddr:           exact;
            hdr.ipv4.dstAddr:           exact;
        }

        // we define no action here, as this table has only debug purposes
        actions = { NoAction; }
        // define the default noaction for each match
        const default_action = NoAction();
    }

    //what to apply for this debug ingress processing
    apply
    {
        ip_debug_table.apply();
    }

}
#endif //ENABLE_DEBUG_IP


#if defined(ENABLE_DEBUG_TCP) || defined(ENABLE_DEBUG_TCP_EGRESS)
control tcp_debug(in headers hdr,
                          inout metadata meta,
                          in standard_metadata_t standard_metadata)
{
    //define debug table
    table tcp_debug_table
    {
        //define keys to match/debug - comment/uncomment to see in log
        key =
        {
            standard_metadata.ingress_port:  exact;
            meta.tcp_metadata.full_length:   exact;
            meta.tcp_metadata.header_length: exact;
            meta.tcp_metadata.payload_length:exact;
            meta.tcp_metadata.payload_length_in_bytes: exact;
            hdr.tcp.srcPort:                 exact;
            hdr.tcp.dstPort:                 exact;
            hdr.tcp.seqNo:                   exact;
            hdr.tcp.ackNo:                   exact;
            hdr.tcp.dataOffset:              exact;
            hdr.tcp.flags_1:                 exact;
            hdr.tcp.flags_2:                 exact;
            hdr.tcp.flags_3:                 exact;
            hdr.tcp.window:                  exact;
            hdr.tcp.checksum:                exact;
            hdr.tcp.urgentPtr:               exact;
        }

        // we define no action here, as this table has only debug purposes
        actions = { NoAction; }
        // define the default noaction for each match
        const default_action = NoAction();
    }

    //what to apply for this debug ingress processing
    apply
    {
        tcp_debug_table.apply();
    }

}
#endif //ENABLE_DEBUG_TCP

#if defined(ENABLE_DEBUG_UDP) || defined(ENABLE_DEBUG_UDP_EGRESS)
control udp_debug(in headers hdr,
                          inout metadata meta,
                          in standard_metadata_t standard_metadata)
{
        //define debug table
        table udp_debug_table
        {
            //define keys to match/debug
            key =
            {
                meta.udp_metadata.udp_len:       exact;
                standard_metadata.ingress_port : exact;
                hdr.udp.srcPort:                 exact;
                hdr.udp.dstPort:                 exact;
                hdr.udp.checksum:                exact;
                hdr.udp.len:                     exact;
                hdr.udp.payload:                 exact;

            }
            // we define no action here, as this table has only debug purposes
            actions = { NoAction; }
            // define the default noaction for each match
            const default_action = NoAction();
        }

        //what to apply for this debug ingress processing
        apply
        {
            udp_debug_table.apply();
        }
}
#endif // ENABLE_DEBUG_UDP


#if defined(ENABLE_DEBUG_META) || defined(ENABLE_DEBUG_META_EGRESS)
control meta_debug(inout metadata meta)
{
    //define meta table
    table meta_debug_table
    {
        //define keys to match
        key =
        {
            meta.modified:                              exact;
            meta.udp_metadata.udp_payload_length:       exact;
            meta.tcp_metadata.header_length:            exact;
            meta.tcp_metadata.header_length_in_bytes:   exact;
            meta.tcp_metadata.payload_length:           exact;
            meta.tcp_metadata.payload_length_in_bytes:  exact;
            meta.tcp_metadata.full_length:              exact;
            meta.tcp_metadata.full_length_in_bytes:     exact;
        }
        //we define no action here as this
        actions = { NoAction; }
        // define the default noaction for each match
        const default_action = NoAction();
    }
    //what to apply for this debug ingress processing
    apply
    {
        meta_debug_table.apply();
    }
}

#endif // ENABLE_DEBUG_META

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata)
{
    // @userextern @name("my_extern_increase")
    // ExternIncrease(0x01) my_extern_increase;


    //create an instance of the debug ingress processing
    #ifdef ENABLE_DEBUG_ETHERNET
        ethernet_debug() ethernet_debug_start;
    #endif //ENABLE_DEBUG_ETHERNET

    #ifdef ENABLE_DEBUG_ARP
        arp_debug() arp_debug_start;
    #endif //ENABLE_DEBUG_ARP

    #ifdef ENABLE_DEBUG_IP
        ip_debug() ip_debug_start;
    #endif //ENABLE_DEBUG_IP

    #ifdef ENABLE_DEBUG_TCP
        tcp_debug() tcp_debug_start;
    #endif //ENABLE_DEBUG_TCP

    #ifdef ENABLE_DEBUG_UDP
        udp_debug() udp_debug_start;
    #endif //ENABLE_DEBUG_UDP

    #ifdef ENABLE_DEBUG_META
        meta_debug() meta_debug_start;
    #endif //ENABLE_DEBUG_META


    action drop()
    {
        mark_to_drop();
    }

    // ----------------- PORT FORWARD ACTIONS AND RULES -------------------
    action portfwd(egressSpec_t port)
    {
	p4_logger(hdr.ipv4.srcAddr);
	p4_logger(hdr.ipv4.hdrChecksum);
	p4_logger((bit<64>)0x3FF199999999999A);

        standard_metadata.egress_spec = port;
    }
    table port_exact
    {
        key =
        {
            standard_metadata.ingress_port: exact;
        }
        actions =
        {
            portfwd;
            drop;
        }
        // size = 10;
        default_action = drop;
        const entries =
        {
            0 : portfwd(1);
            1 : portfwd(0);
        }
    }


    apply
    {
        if(hdr.ethernet.isValid())
        {
                #ifdef ENABLE_DEBUG_ETHERNET
                    ethernet_debug_start.apply(hdr, meta, standard_metadata);
                #endif //ENABLE_DEBUG_ETHERNET

            if(hdr.ethernet.etherType == TYPE_ARP)
            {
                #ifdef ENABLE_DEBUG_ARP
                    arp_debug_start.apply(hdr,meta, standard_metadata);
                #endif //ENABLE_DEBUG_ARP
            }
            else
            {

                if(hdr.ipv4.isValid())
                {
                    #ifdef ENABLE_DEBUG_IP
                        ip_debug_start.apply(hdr, meta, standard_metadata);
                    #endif //ENABLE_DEBUG_IP


                    if(hdr.ipv4.protocol == IP_PROTO_TCP)// && hdr.tcp.isValid())
                    {
                        #ifdef ENABLE_DEBUG_TCP
                            tcp_debug_start.apply(hdr, meta, standard_metadata);
                        #endif //ENABLE_DEBUG_TCP

                    }
                    else if(hdr.ipv4.protocol == IP_PROTO_UDP)// && hdr.udp.isValid())
                    {
                        #ifdef ENABLE_DEBUG_UDP
                            udp_debug_start.apply(hdr, meta, standard_metadata);
                        #endif //ENABLE_DEBUG_UDP
                    }
                }
        }

            #ifdef ENABLE_DEBUG_META
                meta_debug_start.apply(meta);
            #endif //ENABLE_DEBUG_META

            //do the actual forwarding by applying port_exact table and its actions
            port_exact.apply();

        }
    }
}

/************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata)
{

    //create an instance of the debug ingress processing
    #ifdef ENABLE_DEBUG_ETHERNET_EGRESS
        ethernet_debug() ethernet_debug_start;
    #endif // ENABLE_DEBUG_ETHERNET_EGRESS

    #ifdef ENABLE_DEBUG_ARP_EGRESS
        arp_debug() arp_debug_start;
    #endif //ENABLE_DEBUG_ARP_EGRESS

    #ifdef ENABLE_DEBUG_IP_EGRESS
        ip_debug() ip_debug_start;
    #endif //ENABLE_DEBUG_IP_EGRESS

    #ifdef ENABLE_DEBUG_TCP_EGRESS
        tcp_debug() tcp_debug_start;
    #endif //ENABLE_DEBUG_TCP_EGRESS

    #ifdef ENABLE_DEBUG_UDP_EGRESS
        udp_debug() udp_debug_start;
    #endif //ENABLE_DEBUG_UDP_EGRESS

    #ifdef ENABLE_DEBUG_META_EGRESS
        meta_debug() meta_debug_start;
    #endif //ENABLE_DEBUG_META_EGRESS


    apply
    {
            if(hdr.ethernet.isValid())
            {
                #ifdef ENABLE_DEBUG_ETHERNET_EGRESS
                    ethernet_debug_start.apply(hdr, meta, standard_metadata);
                #endif

                if(hdr.ethernet.etherType == TYPE_ARP)
                {
                    #ifdef ENABLE_DEBUG_ARP_EGRESS
                        arp_debug_start.apply(hdr,meta, standard_metadata);
                    #endif //ENABLE_DEBUG_ARP_EGRESS
                }
                else
                {
                    if(hdr.ipv4.isValid())
                    {
                        #ifdef ENABLE_DEBUG_IP_EGRESS
                            ip_debug_start.apply(hdr, meta, standard_metadata);
                        #endif

                        if(hdr.ipv4.protocol == IP_PROTO_TCP)
                        {
                            #ifdef ENABLE_DEBUG_TCP_EGRESS
                                tcp_debug_start.apply(hdr, meta, standard_metadata);
                            #endif
                        }
                        else if(hdr.ipv4.protocol == IP_PROTO_UDP)
                        {
                            #ifdef ENABLE_DEBUG_UDP_EGRESS
                                udp_debug_start.apply(hdr, meta, standard_metadata);
                            #endif
                        }
                    }

                }
            }

            #ifdef ENABLE_DEBUG_META_EGRESS
                meta_debug_start.apply(meta);
            #endif //ENABLE_DEBUG_META_EGRESS

    }
}

/************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta)
{
    apply
    {
       //we don't need any checksum recomputation as packets are intact

    }
}


/************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr)
{
    apply
    {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.arp);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);

    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
