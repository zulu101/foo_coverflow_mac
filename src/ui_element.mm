#import "stdafx.h"
#import "CoverflowViewController.h"

namespace {
// {6C1F4B2E-8A3D-4E57-9B21-3F0D7C5A9E14}
constexpr GUID guid_coverflow_element =
    {0x6c1f4b2e, 0x8a3d, 0x4e57, {0x9b, 0x21, 0x3f, 0x0d, 0x7c, 0x5a, 0x9e, 0x14}};

class coverflow_ui_element : public ui_element_mac {
public:
    service_ptr instantiate(service_ptr arg) override {
        (void)arg;
        return fb2k::wrapNSObject([FCFCoverflowViewController new]);
    }

    bool match_name(const char* name) override {
        return pfc::stricmp_ascii(name, "coverflow") == 0;
    }

    fb2k::stringRef get_name() override {
        return fb2k::makeString("Coverflow");
    }

    GUID get_guid() override {
        return guid_coverflow_element;
    }
};

FB2K_SERVICE_FACTORY(coverflow_ui_element);
} // namespace
