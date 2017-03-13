// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#pragma once

#include <ddk/binding.h>
#include <ddk/device.h>
#include <ddk/protocol/intel-hda-codec.h>
#include <intel-hda-driver-utils/codec-commands.h>
#include <intel-hda-driver-utils/driver-channel.h>
#include <intel-hda-driver-utils/intel-hda-registers.h>
#include <magenta/device/intel-hda.h>
#include <mx/handle.h>
#include <mxtl/mutex.h>
#include <mxtl/mutex.h>
#include <mxtl/ref_counted.h>
#include <mxtl/ref_ptr.h>
#include <mxtl/unique_ptr.h>
#include <stdint.h>
#include <string.h>

#include "codec-cmd-job.h"
#include "intel-hda-device.h"
#include "intel-hda-stream.h"

class IntelHDAController;
struct CodecResponse;

class IntelHDACodec : public IntelHDADevice<IntelHDACodec> {
public:
    // Definition of the client request buffer, exported for IntelHDADevice<>
    union RequestBufferType {
        union {
            ihda_cmd_hdr_t       hdr;
            GetIDsReq            get_ids;
            SendCORBCmdReq       corb_cmd;
            RequestStreamReq     request_stream;
            ReleaseStreamReq     release_stream;
            SetStreamFmtReq      set_stream_fmt;
        } codec;

        IntelHDAStream::RequestBufferType stream_requests;
    };

    enum class State {
        PROBING,
        FINDING_DRIVER,
        OPERATING,
        SHUTTING_DOWN,
        SHUT_DOWN,
        FATAL_ERROR,
    };

    static mxtl::RefPtr<IntelHDACodec> Create(IntelHDAController& controller, uint8_t codec_id);

    void PrintDebugPrefix() const;
    mx_status_t Startup();
    void ProcessSolicitedResponse(const CodecResponse& resp, mxtl::unique_ptr<CodecCmdJob>&& job);
    void ProcessUnsolicitedResponse(const CodecResponse& resp);
    void ProcessWakeupEvt();

    // TODO (johngro) : figure out shutdown... Currently, this is called from
    // the controller's irq thread and expected to execute synchronously, which
    // does not allow codec drivers any oppertunity to perform a graceful
    // shutdown.
    void BeginShutdown();
    void FinishShutdown();

    uint8_t id()  const { return codec_id_; }
    State state() const { return state_; }

    // Debug/Diags
    void DumpState();

protected:
    // DriverChannel::Owner notification
    void NotifyChannelDeactivated(const DriverChannel& channel) final;

private:
    friend class mxtl::RefPtr<IntelHDACodec>;

    using ProbeParseCbk = mx_status_t (IntelHDACodec::*)(const CodecResponse& resp);
    struct ProbeCommandListEntry {
        CodecVerb     verb;
        ProbeParseCbk parse;
    };

    static constexpr size_t PROP_PROTOCOL    = 0;
    static constexpr size_t PROP_VID         = 1;
    static constexpr size_t PROP_DID         = 2;
    static constexpr size_t PROP_MAJOR_REV   = 3;
    static constexpr size_t PROP_MINOR_REV   = 4;
    static constexpr size_t PROP_VENDOR_REV  = 5;
    static constexpr size_t PROP_VENDOR_STEP = 6;
    static constexpr size_t PROP_COUNT       = 7;

    static mx_protocol_device_t CODEC_DEVICE_THUNKS;
    static ihda_codec_protocol_t CODEC_PROTO_THUNKS;

    IntelHDACodec(IntelHDAController& controller, uint8_t codec_id);
    virtual ~IntelHDACodec() { DEBUG_ASSERT(state_ == State::SHUT_DOWN); }

    mx_status_t PublishDevice();

    void SendCORBResponse(const mxtl::RefPtr<DriverChannel>& channel,
                          const CodecResponse& resp,
                          uint32_t transaction_id = IHDA_INVALID_TRANSACTION_ID);

    // Parsers for device probing
    mx_status_t ParseVidDid(const CodecResponse& resp);
    mx_status_t ParseRevisionId(const CodecResponse& resp);

    // MX_PROTOCOL_IHDA_CODEC Interface
    mx_status_t CodecGetDriverChannel(mx_handle_t* channel_out);

    // Get a reference to the active stream (if any) associated with the specified channel.
    mxtl::RefPtr<IntelHDAStream> GetStreamForChannel(const DriverChannel& channel,
                                                     bool* is_stream_channel_out = nullptr);

    // Implementation of IntelHDADevice<> callback and codec specific request
    // processors.
    friend class IntelHDADevice<IntelHDACodec>;
    mx_status_t ProcessClientRequest(DriverChannel& channel,
                                     const RequestBufferType& req,
                                     uint32_t req_size,
                                     mx::handle&& rxed_handle)
        TA_REQ(process_lock());

    mx_status_t ProcessGetIDs(DriverChannel& channel, const GetIDsReq& req)
        TA_REQ(process_lock());
    mx_status_t ProcessSendCORBCmd(DriverChannel& channel, const SendCORBCmdReq& req)
        TA_REQ(process_lock());
    mx_status_t ProcessRequestStream(DriverChannel& channel, const RequestStreamReq& req)
        TA_REQ(process_lock());
    mx_status_t ProcessReleaseStream(DriverChannel& channel, const ReleaseStreamReq& req)
        TA_REQ(process_lock());
    mx_status_t ProcessSetStreamFmt(DriverChannel& channel, const SetStreamFmtReq& req)
        TA_REQ(process_lock());

    // Reference to our owner.
    IntelHDAController& controller_;

    // State management.
    State state_ = State::PROBING;
    uint probe_rx_ndx_ = 0;

    // Driver connection state
    mxtl::Mutex codec_driver_channel_lock_;
    mxtl::RefPtr<DriverChannel> codec_driver_channel_ TA_GUARDED(codec_driver_channel_lock_);

    // Device properties.
    const uint8_t codec_id_;
    mx_device_prop_t dev_props_[PROP_COUNT];
    mx_device_t dev_node_;

    // Active DMA streams
    mxtl::Mutex          active_streams_lock_;
    IntelHDAStream::Tree active_streams_ TA_GUARDED(active_streams_lock_);

    static ProbeCommandListEntry PROBE_COMMANDS[];
};