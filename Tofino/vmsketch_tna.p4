/* -*- P4_16 -*- */
#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

const bit<16> TYPE_IPV4 = 0x0800;

// ---------- Types / headers ----------
typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_h {
  macAddr_t dstAddr;
  macAddr_t srcAddr;
  bit<16>   etherType;
}
header ipv4_h {
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

// ---------- Ingress hdr/meta ----------
struct my_ingress_headers_t { ethernet_h ethernet; ipv4_h ipv4; }
struct my_ingress_metadata_t {
  bit<32> virt_val;
  bit<32> idxC;
  bit<16> cand16;
}

// ---------- Egress hdr/meta ----------
struct my_egress_headers_t { ethernet_h ethernet; ipv4_h ipv4; }
struct my_egress_metadata_t { }

// ---------- VMSketch state ----------
// Use powers of two (avoids modulo & 64-bit math issues)
const bit<32> L = 4096;   // rows in A (2^12)
const bit<32> W = 65536;  // buckets in C (2^16)

// Registers: Register<value_t, index_t>(size)
Register<bit<32>, bit<32>>(L) regA;
Register<bit<16>, bit<32>>(W) regC;

// CRC32 hash externs
Hash<bit<32>>(HashAlgorithm_t.CRC32) h_crc32_a; // src -> idxA
Hash<bit<32>>(HashAlgorithm_t.CRC32) h_crc32_c; // (dst,virt) -> hC

/**************** I N G R E S S  P A R S E R ****************/
parser MyIngressParser(packet_in pkt,
                       out my_ingress_headers_t hdr,
                       out my_ingress_metadata_t meta,
                       out ingress_intrinsic_metadata_t ig_intr_md) {
  state start {
    pkt.extract(ig_intr_md);
    pkt.advance(PORT_METADATA_SIZE);

    // init 'out' metadata (compiler requires)
    meta.virt_val = 0;
    meta.idxC     = 0;
    meta.cand16   = 0;

    transition parse_ethernet;
  }
  state parse_ethernet {
    pkt.extract(hdr.ethernet);
    transition select(hdr.ethernet.etherType) {
      TYPE_IPV4: parse_ipv4;
      default:   accept;
    }
  }
  state parse_ipv4 { pkt.extract(hdr.ipv4); transition accept; }
}

/**************** I N G R E S S  C O N T R O L ****************/
control MyIngress(inout my_ingress_headers_t hdr,
                  inout my_ingress_metadata_t meta,
                  in    ingress_intrinsic_metadata_t               ig_intr_md,
                  in    ingress_intrinsic_metadata_from_parser_t   ig_prsr_md,
                  inout ingress_intrinsic_metadata_for_deparser_t  ig_dprsr_md,
                  inout ingress_intrinsic_metadata_for_tm_t        ig_tm_md) {

  action set_out_port(egressSpec_t port) {
    ig_tm_md.ucast_egress_port = port;   // this image has no *_valid bit
  }

  // ---- Stage 1: ONLY regA ----
  action vm_stage1() {
    // idxA = CRC32(src) & (L-1)  (L=4096 => 0xFFF)
    bit<32> hA   = h_crc32_a.get({ hdr.ipv4.srcAddr });
    bit<32> idxA = hA & 0xFFF;

    // read regA and stash virt_val
    meta.virt_val = regA.read(idxA);

    // hC = CRC32(dst, virt), idxC = hC & (W-1), cand16 = high 16 of hC
    bit<32> hC  = h_crc32_c.get({ hdr.ipv4.dstAddr, meta.virt_val });
    meta.idxC   = hC & 0xFFFF;                 // W=65536 => 0xFFFF
    meta.cand16 = (bit<16>)(hC >> 16);         // candidate
  }

  table vm_stage1_tbl {
    actions = { vm_stage1; }
    size = 1;
    default_action = vm_stage1();
  }

  // ---- Stage 2: ONLY regC ----
  action vm_stage2() {
    bit<16> cur  = regC.read(meta.idxC);
    bit<16> newv = (meta.cand16 < cur) ? meta.cand16 : cur; // single unconditional write
    regC.write(meta.idxC, newv);
  }

  table vm_stage2_tbl {
    actions = { vm_stage2; }
    size = 1;
    default_action = vm_stage2();
  }

  table l2_fwd {
    key = { hdr.ethernet.dstAddr : exact; }
    actions = { set_out_port; NoAction; }
    size = 1024;
    default_action = NoAction();
  }

  apply {
    if (hdr.ipv4.isValid()) {
      vm_stage1_tbl.apply();   // touches regA
      vm_stage2_tbl.apply();   // touches regC
    }
    l2_fwd.apply();
  }
}

/************ I N G R E S S  D E P A R S E R ************/
control MyIngressDeparser(packet_out pkt,
                          inout my_ingress_headers_t hdr,
                          in    my_ingress_metadata_t  meta,
                          in    ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {
  apply {
    pkt.emit(hdr.ethernet);
    if (hdr.ipv4.isValid()) { pkt.emit(hdr.ipv4); }
  }
}

/**************** E G R E S S  P A R S E R ****************/
parser MyEgressParser(packet_in pkt,
                      out my_egress_headers_t hdr,
                      out my_egress_metadata_t meta,
                      out egress_intrinsic_metadata_t eg_intr_md) {
  state start { pkt.extract(eg_intr_md); transition parse_ethernet; }
  state parse_ethernet { transition accept; }
}

/**************** E G R E S S  C O N T R O L ****************/
control MyEgress(inout my_egress_headers_t hdr,
                 inout my_egress_metadata_t meta,
                 in    egress_intrinsic_metadata_t                 eg_intr_md,
                 in    egress_intrinsic_metadata_from_parser_t     eg_prsr_md,
                 inout egress_intrinsic_metadata_for_deparser_t    eg_dprsr_md,
                 inout egress_intrinsic_metadata_for_output_port_t eg_oport_md) {
  apply { }
}

/************ E G R E S S  D E P A R S E R ************/
control MyEgressDeparser(packet_out pkt,
                         inout my_egress_headers_t hdr,
                         in    my_egress_metadata_t  meta,
                         in    egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {
  apply {
    pkt.emit(hdr.ethernet);
    if (hdr.ipv4.isValid()) { pkt.emit(hdr.ipv4); }
  }
}

/**************** F I N A L  P A C K A G E ****************/
Pipeline(
  MyIngressParser(), MyIngress(), MyIngressDeparser(),
  MyEgressParser(),  MyEgress(),  MyEgressDeparser()
) pipe;

Switch(pipe) main;
