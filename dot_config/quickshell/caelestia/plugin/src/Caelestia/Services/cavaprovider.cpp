// ============================================================================
// 本地覆盖层（dotfiles: dot_config/quickshell/caelestia/.../cavaprovider.cpp）
//
// ⚠ 这个文件不是上游原版，是 dotfiles 覆盖层的一部分。install.sh 的
//   install_caelestia_plugin 会在编译前把 dot_config/quickshell/caelestia
//   下的文件盖到 ~/src/caelestia-plugin-src 上（改动用「CAELESTIA LOCAL」
//   注释块标出）。上游更新本文件时，需要人工比对后同步这份覆盖版。
//
// 与上游的差异（唯一一处）：让 FFTW planner 线程安全。
//
// ── 为什么必须改 ─────────────────────────────────────────────
// 崩溃现场（~/.cache/quickshell/crashes/，2026-09-30 共 9 次）：
//     Signal: 段错误 (11)
//     #5  fftw_measure_execution_time   (libfftw3)
//     ...
//     #49 fftw_plan_dft_r2c_1d          (libfftw3)
//     #50 cava_init                     (libcava)
//     #51 CavaProcessor::initCava()     cavaprovider.cpp:102
//
// 根因：FFTW 的 planner（fftw_plan_* / fftw_destroy_plan / wisdom 管理）
// 是**全局且非线程安全**的 —— 官方文档明确：只有 fftw_execute 系列（及其
// new-array 变体）可以多线程并发，建 plan 必须「单线程或加锁」，除非先调
// fftw_make_planner_thread_safe()。
//
// 而 end4-pC 这个 shell 里有**两个** CavaProvider 实例，各自在独立的
// QThread 上工作：
//   · custom-island/CavaService.qml（灵动岛频谱，bars=32）
//   · modules/ii/mediaControls/MediaControls.qml 的 cavaBridge（bars=50）
// 两者都跟着「有没有在放音乐」启停。音乐一开始，两个实例几乎同时排队
// cava_init（setBars → reload → initCava 都走 QueuedConnection），于是
// 两个线程并发进入 FFTW planner，全局 planner 状态被写坏 → 段错误。
// 这就是 end4-pC 壳的崩溃循环：crash → 自动重启 → 放歌 → 再 crash。
//
// 修复：FFTW ≥3.3.5 提供了官方开关 fftw_make_planner_thread_safe()，
// 在插件加载时（命名空间作用域动态初始化，dlopen 时即执行，早于任何
// cava_init）打开它，planner 内部自加锁。对单线程路径零影响（只是多一层
// 已无人争用的锁），对两条频谱链路则消除了唯一的竞态窗口。
//
// 不改 CMakeLists：符号通过 dlopen/dlsym 在运行时解析（见下）。
// ⚠ Arch 的 fftw 包把 fftw_make_planner_thread_safe 放在 libfftw3_threads.so.3
//   （nm -D 实测，主库 libfftw3.so.3 没有这个符号），而链接期走 libcava 的
//   传递依赖只能看到主库 —— 直接调用会在 dlopen 阶段报 undefined symbol
//   （2026-09-30 实测踩坑）。所以这里不硬链接，按「主库优先、threads 库兜底」
//   的顺序 dlsym 查找，跨发行版打包差异也不受影响。
// ============================================================================

#include "cavaprovider.hpp"

#include <qloggingcategory.h>

#include <cava/cavacore.h>

#include <cstddef>

#include <dlfcn.h>

#include "audiocollector.hpp"
#include "audioprovider.hpp"

namespace {

Q_LOGGING_CATEGORY(lcCava, "caelestia.services.cava", QtInfoMsg)
Q_LOGGING_CATEGORY(lcCavaProcessor, "caelestia.services.cava.processor", QtInfoMsg)

// CAELESTIA LOCAL：见文件头注释。插件加载时即把 FFTW planner 切到线程安全
// 模式 —— 命名空间作用域的动态初始化在 dlopen 阶段执行，必然早于任何
// CavaProvider 实例的 cava_init。
[[maybe_unused]] const bool kFftwPlannerThreadSafe = [] {
    using MakePlannerThreadSafeFn = void (*)();
    // 主库优先（上游/多数发行版布局），Arch 的 threads 库兜底。
    for (const char* lib : { "libfftw3.so.3", "libfftw3_threads.so.3" }) {
        if (void* handle = dlopen(lib, RTLD_NOW | RTLD_GLOBAL)) {
            // 先清一次历史错误，避免污染后续判断
            (void)dlerror();
            if (auto fn = reinterpret_cast<MakePlannerThreadSafeFn>(
                    dlsym(handle, "fftw_make_planner_thread_safe"))) {
                fn();
                qCInfo(lcCava) << "FFTW planner 已切换为线程安全模式（via" << lib << "）";
                return true;
            }
        }
    }
    qCWarning(lcCava) << "未找到 fftw_make_planner_thread_safe，FFTW planner 保持默认（非线程安全）模式";
    return false;
}();

} // namespace

namespace caelestia::services {

CavaProcessor::CavaProcessor(QObject* parent)
    : AudioProcessor(parent)
    , m_plan(nullptr)
    , m_in(new double[ac::k_chunkSize])
    , m_out(nullptr)
    , m_bars(0) {};

CavaProcessor::~CavaProcessor() {
    cleanup();
    delete[] m_in;
}

void CavaProcessor::process() {
    if (!m_plan || m_bars == 0 || !m_out) {
        return;
    }

    const int count = static_cast<int>(AudioCollector::instance().readChunk(m_in));

    // Process in data via cava
    cava_execute(m_in, count, m_out, m_plan);

    // Apply monstercat filter
    QVector<double> values(m_bars);

    // Left to right pass
    const double inv = 1.0 / 1.5;
    double carry = 0.0;
    for (int i = 0; i < m_bars; ++i) {
        carry = std::max(m_out[i], carry * inv);
        values[i] = carry;
    }

    // Right to left pass and combine
    carry = 0.0;
    for (int i = m_bars - 1; i >= 0; --i) {
        carry = std::max(m_out[i], carry * inv);
        values[i] = std::max(values[i], carry);
    }

    // Update values
    if (values != m_values) {
        m_values = std::move(values);
        emit valuesChanged(m_values);
    }
}

void CavaProcessor::setBars(int bars) {
    if (bars < 0) {
        qCWarning(lcCavaProcessor) << "setBars: bars must be greater than 0. Setting to 0.";
        bars = 0;
    }

    if (m_bars != bars) {
        m_bars = bars;
        reload();
    }
}

void CavaProcessor::reload() {
    cleanup();
    initCava();
}

void CavaProcessor::cleanup() {
    if (m_plan) {
        cava_destroy(m_plan);
        m_plan = nullptr;
    }

    if (m_out) {
        delete[] m_out;
        m_out = nullptr;
    }
}

void CavaProcessor::initCava() {
    if (m_plan || m_bars == 0) {
        return;
    }

    m_plan = cava_init(m_bars, ac::k_sampleRate, 1, 1, 0.85, 50, 10000);
    m_out = new double[static_cast<size_t>(m_bars)];
}

CavaProvider::CavaProvider(QObject* parent)
    : AudioProvider(parent)
    , m_bars(0)
    , m_values(m_bars, 0.0) {
    m_processor = new CavaProcessor();
    init();

    connect(static_cast<CavaProcessor*>(m_processor), &CavaProcessor::valuesChanged, this, &CavaProvider::updateValues);
}

int CavaProvider::bars() const {
    return m_bars;
}

void CavaProvider::setBars(int bars) {
    if (bars < 0) {
        qCWarning(lcCava) << "setBars: bars must be greater than 0. Setting to 0.";
        bars = 0;
    }

    if (m_bars == bars) {
        return;
    }

    m_values.resize(bars, 0.0);
    m_bars = bars;
    emit barsChanged();
    emit valuesChanged();

    QMetaObject::invokeMethod(
        static_cast<CavaProcessor*>(m_processor), &CavaProcessor::setBars, Qt::QueuedConnection, bars);
}

QVector<double> CavaProvider::values() const {
    return m_values;
}

void CavaProvider::updateValues(const QVector<double>& values) {
    if (values != m_values) {
        m_values = values;
        emit valuesChanged();
    }
}

} // namespace caelestia::services
