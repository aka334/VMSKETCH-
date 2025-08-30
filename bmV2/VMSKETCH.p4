// VMSketch (BMv2 / v1model) — reference P4_16 implementation
// Target: BMv2 simple_switch (v1model)

#include <core.p4>
#include <v1model.p4>

const bit<32> L = 5000;
const bit<32> W = 65536;
const bit<16> C_INIT = 0xFFFF;

typedef bit<48> mac_addr_t;
typedef bit<16> ether_type_t;
typedef bit<32> ipv4_addr_t;

header ethernet_t {
    mac_addr_t  dstAddr;
    mac_addr_t  srcAddr;
    ether_type_t etherType;
};

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
    ipv4_addr_t srcAddr;
    ipv4_addr_t dstAddr;
};

struct headers {
    ethernet_t ethernet;
    ipv4_t     ipv4;
};

struct metadata { };

register<bit<32>>(L) regA;
register<bit<16>>(W) regC;

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    action set_out_port(bit<9> port) {
        standard_metadata.egress_spec = port;
    }

    table l2_fwd {
        key = {
            hdr.ethernet.dstAddr : exact;
        }
        actions = {
            set_out_port;
            NoAction;
        }
        size = 1024;
        default_action = NoAction();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            bit<32> idxA;
            hash(idxA, HashAlgorithm.crc32, (bit<32>)0, { hdr.ipv4.srcAddr }, L);

            bit<32> virt_val;
            regA.read(virt_val, idxA);

            bit<32> idxC;
            hash(idxC, HashAlgorithm.crc32, (bit<32>)0, { hdr.ipv4.dstAddr, virt_val }, W);

            bit<16> cand;
            hash(cand, HashAlgorithm.crc16, (bit<16>)0, { hdr.ipv4.dstAddr, virt_val }, W);

            bit<16> cur;
            regC.read(cur, idxC);
            if (cand < cur) {
                regC.write(idxC, cand);
            }
        }

        l2_fwd.apply();
    }
}

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        // BMv2/v1model deparser does not support if-statements.
        // Emitting an invalid header is a no-op, so we can emit unconditionally.
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

V1Switch(
    MyParser(),
    MyVerifyChecksum(),
    MyIngress(),
    MyEgress(),
    MyComputeChecksum(),
    MyDeparser()
) main;
