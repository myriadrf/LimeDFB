HostTCD TX
==========

HostTCD TX transfers samples from separate host DMA buffers into the FPGA for
timestamped playback on the selected channels. Large parent descriptors reduce
host submission overhead, while smaller FPGA buffers allow DMA prefetch and
playback to overlap.

HostTCD table and descriptor handling
-------------------------------------

The host submits large parent descriptors containing one source DMA address
per participating channel, the payload length per channel, the sample format
and the timestamp of the first sample. The FPGA splits each parent into chunks
of ``split_size`` bytes per channel, with each chunk fitting one TX buffer.
Parents contain a whole number of chunks.

.. figure:: images/host_tcd_tx_chunks.drawio.svg
   :width: 100%
   :alt: Parent split into chunks, three TX buffers per channel, and a sample timeline showing late chunks discarded while later chunks retain their timestamps

   HostTCD TX descriptor splitting and timestamp recovery. In the example,
   chunk 1 is late and chunk 2 has insufficient preparation time. Playback
   resumes with chunk 3 at its original timestamp, leaving a gap across all
   participating channels. Chunk indices and buffer roles are illustrative.

   Editable source: :download:`draw.io diagram <images/host_tcd_tx_chunks.drawio>`.
   The SVG also contains the editable drawing and can be opened in draw.io.

The FPGA maintains at least three buffers per channel. The current HiperSDR
configuration provides three buffers of 4096 complex samples each per channel,
allowing the next chunk to be prefetched while a buffered chunk is transmitted.
All participating channels use the same chunk index and sample offset.

For zero-based chunk index ``i`` and channel ``c``, the source address and
scheduled timestamp are::

   host_address[c] = parent_address[c] + i * split_size_bytes
   tx_timestamp    = parent_timestamp + i * samples_per_chunk

Timestamps advance in sample ticks; DMA addresses advance in bytes. Packed
IQ12 uses 3 bytes per complex sample, while IQ16 uses 4 bytes. A 4096-sample
chunk therefore occupies 12288 bytes per channel for IQ12 or 16384 bytes for
IQ16. Both formats cover the same number of sample ticks.

Before playback, the FPGA fully buffers a chunk for every participating
channel. All channels start together when the shared RX/TX sample counter
matches that chunk's scheduled timestamp.

When a chunk cannot start on time, the FPGA:

* Discards that chunk without shifting subsequent timestamps.
* Selects the earliest remaining chunk with enough lead time for DMA,
  unpacking and scheduling.
* Advances the host address and sample offset consistently across all
  participating channels.
* Rechecks readiness at the selected timestamp and skips again if necessary.
* Discards the remaining parent if no usable chunk remains.

The FPGA avoids issuing DMA reads for skipped chunks. Already-issued
responses are drained or discarded safely before their buffers are reused.
Skipping samples leaves a gap in the original timeline; later chunks retain
their timestamps and can resume in sync.

The FPGA reports one completion per parent, including transmitted and skipped
sample counts and any errors. Host memory remains owned until outstanding DMA
accesses have safely retired; accepting or fetching a descriptor alone does
not release its source buffers.

This architecture preserves the RX/TX timeline through gaps, reduces host
descriptor overhead and overlaps fetching with playback. Continuous output
still requires sufficient DMA throughput, timestamp lead time and buffer depth.
