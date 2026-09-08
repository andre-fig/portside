/* Build with either MinGW target and run only in a disposable Wine prefix.
 * Place a second copy beside this executable named steamwebhelper.exe.
 * This is a console control, not Steam/CEF: no browser sandbox is disabled.
 * Exercise CreateProcessW (where engine compatibility hacks can append flags)
 * and report only fixed diagnostics, never paths or arbitrary command lines. */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

static void report(const char *message)
{
    wchar_t path[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, path, MAX_PATH), written;
    printf("%s", message);
    if (!length || length + 8 >= MAX_PATH) return;
    wcscat(path, L".result");
    HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;
    WriteFile(file, message, (DWORD)strlen(message), &written, NULL);
    CloseHandle(file);
}

int wmain(int argc, wchar_t **argv)
{
    char message[160];
    if (argc > 1 && !wcscmp(argv[1], L"--portside-child"))
    {
        const wchar_t *command = GetCommandLineW();
        int sandbox = wcsstr(command, L"--no-sandbox") != NULL;
        int in_process = wcsstr(command, L"--in-process-gpu") != NULL;
        int disabled_gpu = wcsstr(command, L"--disable-gpu") != NULL;
        int intact = argc == 3 && !wcscmp(argv[2], L"sentinel");
        snprintf(message, sizeof(message),
                 "child argumentsIntact=%d noSandbox=%d inProcessGPU=%d disabledGPU=%d\n",
                 intact, sandbox, in_process, disabled_gpu);
        report(message);
        return intact && !sandbox && !in_process && !disabled_gpu ? 0 : 42;
    }
    wchar_t child[MAX_PATH], command[MAX_PATH * 2];
    DWORD length = GetModuleFileNameW(NULL, child, MAX_PATH);
    if (!length || length >= MAX_PATH) return 43;
    wchar_t *name = wcsrchr(child, L'\\');
    if (!name || name - child + 20 >= MAX_PATH)
        return 43;
    wcscpy(name + 1, L"steamwebhelper.exe");
    if (swprintf(command, MAX_PATH * 2, L"\"%ls\" --portside-child sentinel", child) < 0)
        return 43;
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    startup.cb = sizeof(startup);
    if (!CreateProcessW(child, command, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process))
    {
        snprintf(message, sizeof(message), "child creation failed error=%lu\n", GetLastError());
        report(message);
        return 44;
    }
    DWORD status = 45;
    if (WaitForSingleObject(process.hProcess, 20000) == WAIT_OBJECT_0)
        GetExitCodeProcess(process.hProcess, &status);
    else
        TerminateProcess(process.hProcess, 45); /* Only our created control child. */
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    snprintf(message, sizeof(message), "parent childStatus=%lu\n", status);
    report(message);
    return status;
}
