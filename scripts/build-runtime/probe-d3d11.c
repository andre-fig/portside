/* Diagnostic control compiled with x86_64-w64-mingw32-gcc and run only in
 * a disposable Wine prefix. Reports real device creation, not guessed caps. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>

int main(void)
{
    const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_9_3};
    for (unsigned int i = 0; i < sizeof(levels) / sizeof(levels[0]); ++i)
    {
        ID3D11Device *device = NULL;
        ID3D11DeviceContext *context = NULL;
        D3D_FEATURE_LEVEL actual = 0;
        HRESULT result = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT, &levels[i], 1, D3D11_SDK_VERSION,
            &device, &actual, &context);
        printf("requested=0x%x result=0x%08lx actual=0x%x\n", levels[i], (unsigned long)result, actual);
        if (context) ID3D11DeviceContext_Release(context);
        if (device) ID3D11Device_Release(device);
    }
    return 0;
}
