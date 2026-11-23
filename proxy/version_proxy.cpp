// version.dll proxy for QQNT 9.9.37+
// 1) patches the in-memory file-integrity verifier inside QQNT.dll (signature scan)
// 2) forwards the three VERSION.dll exports QQNT.dll imports
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>

static wchar_t g_logPath[MAX_PATH];

static const wchar_t* GetLogPath() {
    if (g_logPath[0]) return g_logPath;
    wchar_t dir[MAX_PATH] = { 0 };
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", dir, MAX_PATH);
    if (n > 0 && n < MAX_PATH) {
        _snwprintf_s(g_logPath, MAX_PATH, _TRUNCATE, L"%s\\LiteLoaderQQNT\\patch.log", dir);
        wchar_t sub[MAX_PATH];
        _snwprintf_s(sub, MAX_PATH, _TRUNCATE, L"%s\\LiteLoaderQQNT", dir);
        CreateDirectoryW(sub, NULL);
    } else {
        wcscpy_s(g_logPath, MAX_PATH, L"C:\\qqnt_patch.log");
    }
    return g_logPath;
}

static void LogW(const wchar_t* fmt, ...) {
    wchar_t buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = _vsnwprintf_s(buf, 1024, _TRUNCATE, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    HANDLE h = CreateFileW(GetLogPath(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    SetFilePointer(h, 0, NULL, FILE_END);
    DWORD written = 0;
    char utf8[2048];
    int len = WideCharToMultiByte(CP_UTF8, 0, buf, n, utf8, sizeof(utf8), NULL, NULL);
    if (len > 0) WriteFile(h, utf8, len, &written, NULL);
    WriteFile(h, "\r\n", 2, &written, NULL);
    CloseHandle(h);
}

// QQNTFileVerifyPatch x64 signature: mov rsi,rcx; ... ; call <compare>
static const BYTE kSig[] = {
    0x48, 0x89, 0xCE, 0x48, 0x8B, 0x11, 0x4C, 0x8B,
    0x41, 0x08, 0x49, 0x29, 0xD0, 0x48, 0x8B, 0x49,
    0x18, 0xE8
};
static const BYTE kRepl[] = {
    0x48, 0x89, 0xCE, 0x48, 0x8B, 0x11, 0x4C, 0x8B,
    0x41, 0x08, 0x49, 0x29, 0xD0, 0x48, 0x8B, 0x49,
    0x18, 0xB8, 0x01, 0x00, 0x00, 0x00
};

static BYTE* ScanSig(BYTE* start, SIZE_T size) {
    if (size < sizeof(kSig)) return NULL;
    const BYTE first = kSig[0];
    for (SIZE_T i = 0; i + sizeof(kSig) <= size; i++) {
        BYTE* p = (BYTE*)memchr(start + i, first, size - i - sizeof(kSig) + 1);
        if (!p) return NULL;
        i = (SIZE_T)(p - start);
        if (memcmp(p, kSig, sizeof(kSig)) == 0) return p;
    }
    return NULL;
}

static void PatchQQNT() {
    HMODULE qqnt = GetModuleHandleW(L"QQNT.dll");
    if (!qqnt) { LogW(L"[proxy] QQNT.dll not mapped"); return; }

    BYTE* base = (BYTE*)qqnt;
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) { LogW(L"[proxy] bad DOS header"); return; }
    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) { LogW(L"[proxy] bad NT header"); return; }

    IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);
    BYTE* text = NULL;
    SIZE_T textSize = 0;
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections; i++, sec++) {
        if (memcmp(sec->Name, ".text", 5) == 0) {
            text = base + sec->VirtualAddress;
            textSize = sec->Misc.VirtualSize;
            break;
        }
    }
    if (!text) { LogW(L"[proxy] .text not found"); return; }

    BYTE* hit = ScanSig(text, textSize);
    if (!hit) { LogW(L"[proxy] verification signature NOT FOUND - QQ build may have changed"); return; }

    DWORD old = 0;
    if (!VirtualProtect(hit, sizeof(kRepl), PAGE_EXECUTE_READWRITE, &old)) {
        LogW(L"[proxy] VirtualProtect failed %lu", GetLastError());
        return;
    }
    memcpy(hit, kRepl, sizeof(kRepl));
    VirtualProtect(hit, sizeof(kRepl), old, &old);
    FlushInstructionCache(GetCurrentProcess(), hit, sizeof(kRepl));
    LogW(L"[proxy] patched verifier at %p (rva 0x%llX)", hit, (unsigned long long)(hit - base));
}

typedef DWORD  (WINAPI *PFN_GetFileVersionInfoSizeW)(LPCWSTR, LPDWORD);
typedef BOOL   (WINAPI *PFN_GetFileVersionInfoW)(LPCWSTR, DWORD, DWORD, LPVOID);
typedef BOOL   (WINAPI *PFN_VerQueryValueW)(LPCVOID, LPCWSTR, LPVOID*, PUINT);

static HMODULE g_real = NULL;
static void EnsureReal() {
    if (!g_real) {
        g_real = LoadLibraryExW(L"C:\\Windows\\System32\\version.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    }
}

extern "C" __declspec(dllexport) DWORD WINAPI Proxy_GetFileVersionInfoSizeW(LPCWSTR a, LPDWORD b) {
    EnsureReal(); return ((PFN_GetFileVersionInfoSizeW)GetProcAddress(g_real, "GetFileVersionInfoSizeW"))(a, b);
}
extern "C" __declspec(dllexport) BOOL WINAPI Proxy_GetFileVersionInfoW(LPCWSTR a, DWORD b, DWORD c, LPVOID d) {
    EnsureReal(); return ((PFN_GetFileVersionInfoW)GetProcAddress(g_real, "GetFileVersionInfoW"))(a, b, c, d);
}
extern "C" __declspec(dllexport) BOOL WINAPI Proxy_VerQueryValueW(LPCVOID a, LPCWSTR b, LPVOID* c, PUINT d) {
    EnsureReal(); return ((PFN_VerQueryValueW)GetProcAddress(g_real, "VerQueryValueW"))(a, b, c, d);
}

#pragma comment(linker, "/export:GetFileVersionInfoSizeW=Proxy_GetFileVersionInfoSizeW")
#pragma comment(linker, "/export:GetFileVersionInfoW=Proxy_GetFileVersionInfoW")
#pragma comment(linker, "/export:VerQueryValueW=Proxy_VerQueryValueW")

BOOL WINAPI DllMain(HMODULE hModule, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        // only run once per process, only when QQ runtime is present
        if (GetModuleHandleW(L"QQNT.dll")) {
            LogW(L"[proxy] attached pid=%lu", GetCurrentProcessId());
            PatchQQNT();
        }
    }
    return TRUE;
}
