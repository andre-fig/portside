/* Load the fixture's Valve-supplied ANGLE, without replacing any runtime DLL.
 * EGL constants are from Khronos EGL and ANGLE's eglext_angle.h. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc < 3 || argc > 4) { fprintf(stderr, "usage: probe-steam-angle.exe CEF_DIRECTORY BACKEND [SWIFTSHADER]\n"); return 2; }
    SetDllDirectoryA(argv[1]);
    HMODULE egl = LoadLibraryA("libEGL.dll");
    HMODULE gl = LoadLibraryA("libGLESv2.dll");
    if (!egl || !gl) { printf("load-error=%lu\n", GetLastError()); return 1; }
    void *(WINAPI *getProc)(const char *) = (void *)GetProcAddress(egl, "eglGetProcAddress");
    void *(WINAPI *display)(unsigned int, void *, const int *) = getProc("eglGetPlatformDisplayEXT");
    unsigned int (WINAPI *initialize)(void *, int *, int *) = (void *)GetProcAddress(egl, "eglInitialize");
    unsigned int (WINAPI *choose)(void *, const int *, void **, int, int *) = (void *)GetProcAddress(egl, "eglChooseConfig");
    void *(WINAPI *context)(void *, void *, void *, const int *) = (void *)GetProcAddress(egl, "eglCreateContext");
    unsigned int (WINAPI *error)(void) = (void *)GetProcAddress(egl, "eglGetError");
    const char *(WINAPI *query)(void *, int) = (void *)GetProcAddress(egl, "eglQueryString");
    void *(WINAPI *surface)(void *, void *, const int *) = (void *)GetProcAddress(egl, "eglCreatePbufferSurface");
    unsigned int (WINAPI *current)(void *, void *, void *, void *) = (void *)GetProcAddress(egl, "eglMakeCurrent");
    const char *(WINAPI *glString)(unsigned int) = (void *)GetProcAddress(gl, "glGetString");
    void (WINAPI *clearColor)(float, float, float, float) = (void *)GetProcAddress(gl, "glClearColor");
    void (WINAPI *clear)(unsigned int) = (void *)GetProcAddress(gl, "glClear");
    void (WINAPI *pixels)(int,int,int,int,unsigned int,unsigned int,void *) = (void *)GetProcAddress(gl, "glReadPixels");
    if (!display || !initialize || !choose || !context || !error || !query || !surface || !current || !glString || !clearColor || !clear || !pixels) return 3;
    int attrs[] = {0x3203, (int)strtol(argv[2], NULL, 0),
        argc == 4 ? 0x3209 : 0x3038, 0x3487, 0x3038};
    void *d = display(0x3202, NULL, attrs);
    int major=0, minor=0;
    unsigned int ok=initialize(d, &major, &minor);
    printf("initialize=%u error=0x%x EGL=%d.%d\n", ok,error(),major,minor);
    if (!ok) return 4;
    printf("vendor=%s version=%s\n",query(d,0x3053),query(d,0x3054));
    int configAttrs[]={0x3040,4,0x3033,1,0x3024,8,0x3023,8,0x3022,8,0x3021,8,0x3038}; void *config=NULL; int count=0;
    choose(d,configAttrs,&config,1,&count);
    int surfaceAttrs[]={0x3057,4,0x3056,4,0x3038};
    void *pbuffer=surface(d,config,surfaceAttrs);
    int failed=0;
    for (int version=2;version<=3;version++) {
        int contextAttrs[]={0x3098,version,0x3038};
        void *c=context(d,config,NULL,contextAttrs);
        printf("GLES=%d context=%s error=0x%x\n",version,c ? "created" : "failed",error());
        if (!c || !pbuffer || !current(d,pbuffer,pbuffer,c)) { failed=1; continue; }
        printf("renderer=%s version=%s\n",glString(0x1F01),glString(0x1F02));
        unsigned char rgba[4]={0};
        clearColor(0.25f,0.5f,0.75f,1.0f); clear(0x4000);
        pixels(0,0,1,1,0x1908,0x1401,rgba);
        int valid=abs((int)rgba[0]-64)<=1 && abs((int)rgba[1]-128)<=1 && abs((int)rgba[2]-191)<=1 && rgba[3]==255;
        printf("rendered-pixel=%u,%u,%u,%u verified=%d\n",rgba[0],rgba[1],rgba[2],rgba[3],valid);
        if (!valid) failed=1;
    }
    return failed ? 5 : 0;
}
