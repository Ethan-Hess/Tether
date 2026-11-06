// Minimal D3D11 smoke test: creates a window and a hardware device, clears the back buffer to a
// changing colour for ~2 seconds, prints what it got, and exits 0. Exits non-zero on any failure.
//
// Build (x86_64 PE): see build.sh in this directory.
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

static int fail(const char *what, HRESULT hr)
{
    printf("FAIL: %s (hr=0x%08lx)\n", what, (unsigned long)hr);
    fflush(stdout);
    return 1;
}

int main(void)
{
    const int width = 640, height = 360, frames = 120;
    WNDCLASSA wc = { 0 };
    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "TetherD3D11Sample";
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    if (!RegisterClassA(&wc)) return fail("RegisterClass", HRESULT_FROM_WIN32(GetLastError()));

    RECT r = { 0, 0, width, height };
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hwnd = CreateWindowA(wc.lpszClassName, "Tether D3D11 sample", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              100, 100, r.right - r.left, r.bottom - r.top, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) return fail("CreateWindow", HRESULT_FROM_WIN32(GetLastError()));

    DXGI_SWAP_CHAIN_DESC sd = { 0 };
    sd.BufferCount = 2;
    sd.BufferDesc.Width = width;
    sd.BufferDesc.Height = height;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    const D3D_FEATURE_LEVEL want[] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0 };
    D3D_FEATURE_LEVEL got = 0;
    IDXGISwapChain *swap = NULL;
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, want, 3,
                                               D3D11_SDK_VERSION, &sd, &swap, &dev, &got, &ctx);
    if (FAILED(hr)) return fail("D3D11CreateDeviceAndSwapChain", hr);

    IDXGIDevice *dxgi_dev = NULL;
    IDXGIAdapter *adapter = NULL;
    DXGI_ADAPTER_DESC ad = { 0 };
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgi_dev)) &&
        SUCCEEDED(IDXGIDevice_GetAdapter(dxgi_dev, &adapter)) &&
        SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &ad))) {
        char name[128];
        WideCharToMultiByte(CP_UTF8, 0, ad.Description, -1, name, sizeof name, NULL, NULL);
        printf("adapter: %s\n", name);
    }
    printf("feature level: 0x%04x\n", (unsigned)got);

    ID3D11Texture2D *backbuffer = NULL;
    hr = IDXGISwapChain_GetBuffer(swap, 0, &IID_ID3D11Texture2D, (void **)&backbuffer);
    if (FAILED(hr)) return fail("GetBuffer", hr);
    ID3D11RenderTargetView *rtv = NULL;
    hr = ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)backbuffer, NULL, &rtv);
    if (FAILED(hr)) return fail("CreateRenderTargetView", hr);

    int presented = 0;
    for (int i = 0; i < frames; i++) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        float t = (float)i / (float)frames;
        float colour[4] = { t, 0.4f * (1.0f - t), 1.0f - t, 1.0f };
        ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, colour);
        hr = IDXGISwapChain_Present(swap, 1, 0);
        if (FAILED(hr)) return fail("Present", hr);
        presented++;
        Sleep(16);
    }

    printf("presented %d frames\nOK\n", presented);
    fflush(stdout);
    ID3D11RenderTargetView_Release(rtv);
    ID3D11Texture2D_Release(backbuffer);
    ID3D11DeviceContext_Release(ctx);
    ID3D11Device_Release(dev);
    IDXGISwapChain_Release(swap);
    DestroyWindow(hwnd);
    return 0;
}
