#!/usr/bin/env python

import sys

# 2014-06-30
# Efficiently encode a load-time relocatable CP/M image.

# Testing on a sample early CP/M image (2014-06-30) gave the following run length histogram:
#
# length 2 count 55 (4.2%)
# length 3 count 517 (39.7%)
# length 4 count 203 (15.6%)
# length 5 count 178 (13.7%)
# length 6 count 95 (7.3%)
# length 7 count 65 (5.0%)
# length 8 count 45 (3.5%)
# length 9 count 32 (2.5%)
# length 10 count 16 (1.2%)
# length 11 count 18 (1.4%)
# length 12 count 10 (0.8%)
# length 13 count 12 (0.9%)
# length 14 count 9 (0.7%)
# length 15 count 10 (0.8%)
# length 16 or greater count 36 (2.8%)
#  - longest observed run was length 278.
#  - ~97% of runs are under 16 bytes in length
#
# Naive encoding (using early CBIOS code as test payload);
#   1 bit per byte = 12.5% overhead
#   4-bit, 10-bit encoding: 9.3% overhead
#   2-bit, 4-bit, 10-bit encoding: 8.3% overhead
#
# New --bruteforce argument tests numerous combinations of encodings, determined
# best overhead with this technique is just under 8%.

class Encoder(object):
    def __init__(self, params):
        self.bitstream = list()
        self.params = params
        self.cksum = None
    
    def output_bit(self, val):
        self.bitstream.append(val)

    def get_cksum(self):
        return self.cksum

    def get_params(self):
        return self.params

    def get_offsets(self):
        l = list()
        offset = 1
        for x in self.params:
            l.append(offset)
            offset += (1 << x) - 1
        return l
    
    def get_bitstream(self):
        stream = list()
    
        byte = 0
        bits = 0
        for bit in self.bitstream:
            if bit:
                byte = byte | 1
            bits += 1
            if bits == 8:
                stream.append(chr(byte))
                byte = 0
                bits = 0
            else:
                byte = byte << 1
    
        # pretty sure we end up out of alignment here but it doesn't
        # matter since we output just 0s at the end in any event so the
        # final bytes are always 0.
        stream.append(chr(byte))
    
        return ''.join(stream)
    
    def output_integer(self, val, bits):
        # print "Encoding %d bit integer 0x%02x" % (bits, val)
        encoded = list()
        for b in range(bits):
            encoded.append(val & 1)
            val = val >> 1
        for bit in reversed(encoded):
            self.output_bit(bit)
    
    def output_run(self, bytes):
        length = len(bytes)
        # print "Output run length %d bytes" % length
    
        # note that "run" is always 2 or more bytes.
        if length < 2:
            raise RuntimeError('Unexpected run length %d' % length)

        offset = 2
        for width in self.params:
            maxoff = (1 << width) - 1
            if length < (offset + maxoff): # does it fit?
                self.output_integer(length + 1 - offset, width)
                break
            else: # it doesn't fit, output a zero
                self.output_integer(0, width)
                offset += maxoff
        else:
            raise RuntimeError('Cannot fit run length %d' % length)
    
        # in all cases we then pack in the bytes
        for byte in bytes:
            self.output_integer(ord(byte), 8) # data values
    
    def output_eos(self):
        for width in self.params:
            self.output_integer(0, width)
    
    def encode(self, cpm_image1, cpm_image2):
        # compare images and generate the input for the runtime relocator
        expected_diff = 0x80 # expected byte difference, (0x8000 - 0x0000) >> 8
        run = []
        cksum = 0
        for offset, (img_byte, alt_byte) in enumerate(zip(cpm_image1, cpm_image2)):
            cksum = cksum + ord(img_byte)
            if img_byte == alt_byte:
                run.append(img_byte)
            else:
                # verify expected difference
                if ord(alt_byte) - ord(img_byte) != expected_diff:
                    raise RuntimeError('Unexpected difference 0x%02x vs 0x%02x at offset 0x%04x',
                            ord(img_byte), ord(alt_byte), offset)
                self.output_run(run)
                run = [img_byte]
    
        # drain any buffered data
        if run:
            self.output_run(run)
    
        # end of stream
        self.output_eos()
    
        # write out encoded bitstream
        self.cksum = cksum & 0xFFFF

# open and load CP/M images
cpm_image1 = open(sys.argv[1], 'rb').read() # primary image, linked at base 0x0000
cpm_image2 = open(sys.argv[2], 'rb').read() # comparison image, linked at base 0x8000

# check image length matches
if len(cpm_image1) != len(cpm_image2):
    raise RuntimeError('CP/M image length mismatch')

# this performs a brute-force search to determine the optimal encoder
# parameters; this is far from the optimal way to search but it is quicker 
# just to let this run for ten minutes than to write a better program!!
if '--bruteforce' in sys.argv:
    params = list()
    maxbits = 9
    prev = None
    for depth in range(5):
        new = list()
        for b in range(1, 1+maxbits):
            if prev:
                for t in prev:
                    new.append(tuple( [b] + list(t) ))
            else:
                new.append((b,))
        prev = new
        params.extend(new)

    print "Testing %d combinations" % len(params)

    tested = set()
    results = dict()
    for p in params:
        if p in tested:
            print "DUPLICATED %r" % (p,)
        else:
            tested.add(p)
        try:
            encoder = Encoder(p)
            encoder.encode(cpm_image1, cpm_image2)
            l = len(encoder.get_bitstream())
            try:
                results[l].append(p)
            except KeyError:
                results[l] = [p]
        except:
            pass

    for l, encodings in sorted(results.iteritems(), reverse=True):
        print "Bitstream length %d bytes: %d encodings: %r" % (l, len(encodings), encodings)

    encoder_params = encodings[0] # take the first, best solution.
else:
    # use the now-standard parameters;
    encoder_params = (2, 2, 3, 7) # determined by --bruteforced to be best for our payload.
                                  # 2,1,2,3,7 is slightly better but doesn't really save
                                  # any space due to the additional compression parameters.

encoder = Encoder(encoder_params)
encoder.encode(cpm_image1, cpm_image2)
bitstream = encoder.get_bitstream()
cksum = encoder.get_cksum()

open(sys.argv[3], 'wb').write(bitstream)
print "Encoded bitstream is %d bytes, image is %d bytes, %.1f%% overhead" % (
        len(bitstream), len(cpm_image1), 100. * len(bitstream) / len(cpm_image1) - 100.)

payload_fd = open(sys.argv[4], 'w')
payload_fd.write("const unsigned int cpm_image_length = %d;\n" % len(cpm_image1))
payload_fd.write("const unsigned int cpm_image_cksum = %d;\n" % cksum)
payload_fd.write("const unsigned char cpm_image_encoding[] = {%s, 0};\n" % (', '.join('%d' % x for x in encoder.get_params())))
payload_fd.write("const unsigned char cpm_image_offsets[] = {%s};\n" % (', '.join('%d' % x for x in encoder.get_offsets())))
payload_fd.write("const unsigned char cpm_image_data[] = {\n\t")

for n, byte in enumerate(bitstream):
    payload_fd.write("0x%02x, " % ord(byte))
    if n % 10 == 9:
        payload_fd.write("\n\t")

payload_fd.write("\n};\n");
