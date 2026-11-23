// ============================================================================
// MyDanceFramework - L4D2 高自由度跳舞框架 v2.0 (解耦版)
// 基于原版 dance_script_decrypted.nut 提炼，4 模块解耦架构
//
// 模块划分:
//   [主体] DanceController   - 只管 dummy 生命周期 (spawn / play / cleanup)
//   [副体1] MusicController   - 只管音乐 (Emit/Stop + BGM 开关)
//   [副体2] CameraController  - 只管相机三件套 + 真人传送/恢复
//   [副体3] LyricController   - 歌词字幕 (占位，未实现)
//   [配置] DanceConfig        - 所有可变参数集中在此
// ============================================================================

printl("[MyDance] 框架加载成功!");
printl("[MyDance] 聊天命令: !dance <代号> <动作>");
printl("[MyDance]          !mystop (强制停止)");
printl("[MyDance]          !mytest (兼容旧版)");

// ==========================================
// 0. 基础工具函数
// ==========================================

function GetPlayerLookPos(player) {
    local startPt = player.EyePosition();
    local Angle = player.EyeAngles();
    local endPt = startPt + Angle.Forward().Scale(9999);
    local m_trace = { start = startPt, end = endPt, ignore = player, mask = 0xFFFFFFFF };
    TraceLine(m_trace);
    if(m_trace.hit) return m_trace.pos;
    return null;
}

function GetCurrentSurvivorCode(player) {
    // 从 player 的模型路径反推角色代号（简化版）
    local modelPath = player.GetModelName();
    if(modelPath.find("namvet") > -1) return "b";
    if(modelPath.find("teenangst") > -1) return "z";
    if(modelPath.find("manager") > -1) return "l";
    if(modelPath.find("biker") > -1) return "f";
    if(modelPath.find("gambler") > -1) return "n";
    if(modelPath.find("producer") > -1) return "r";
    if(modelPath.find("mechanic") > -1) return "e";
    if(modelPath.find("coach") > -1) return "c";
    return "z"; // fallback
}

// ==========================================
// 1. DanceConfig — 所有可变参数集中在此
// ==========================================

DanceConfig <- {

    // ---- 角色代号 → 固定模型路径 ----
    // 绕开玩家自定义模型替换模组问题（原版硬编码，必须匹配 gestures mdl）
    models = {
        "b" : "models/survivors/survivor_namvet.mdl",    // Bill
        "z" : "models/survivors/survivor_teenangst.mdl",  // Zoey
        "l" : "models/survivors/survivor_manager.mdl",     // Louis
        "f" : "models/survivors/survivor_biker.mdl",      // Francis
        "n" : "models/survivors/survivor_gambler.mdl",     // Nick
        "r" : "models/survivors/survivor_producer.mdl",    // Rochelle
        "e" : "models/survivors/survivor_mechanic.mdl",    // Ellis
        "c" : "models/survivors/survivor_coach.mdl",       // Coach
    },

    // ---- 动作名 → sequence 名 + 音乐路径 ----
    // key 是命令里用的动作名, seq 是 mdl 里的 sequence 名, music 是 mp3 路径
    actions = {
        "d01" : { seq = "d01", music = "music/flu/d01.mp3" },
        "d02" : { seq = "d02", music = "music/flu/d02.mp3" },
        "d03" : { seq = "d03", music = "music/flu/d03.mp3" },
        "d04" : { seq = "d04", music = "music/flu/d04.mp3" },
        "d05" : { seq = "d05", music = "music/flu/d05.mp3" },
        "d06" : { seq = "d06", music = "music/flu/d06.mp3" },
        "d07" : { seq = "d07", music = "music/flu/d07.mp3" },
        "d08" : { seq = "d08", music = "music/flu/d08.mp3" },
        "d09" : { seq = "d09", music = "music/flu/d09.mp3" },
        "d10" : { seq = "d10", music = "music/flu/d10.mp3" },
        // ... 按需扩展, 支持任意自定义名:
        // "my_custom_dance" : { seq = "myseq", music = "music/custom/my.mp3" },
    },

    // ---- 模块开关 ----
    camera = {
        enabled = false,       // MVP 默认关, 等单人无相机跑通再开
        model   = "models/DanceCam/Introcam.mdl",
        fov     = 55,
        spawnflags = 5,
    },

    lyric = {
        enabled = false,       // 占位，未实现
    },

    music = {
        enabled = true,
        volume  = 10,          // 0-10 整数, Source 音量单位
        distance  = 100,
        falloff   = 100,
    },

    dummy = {
        lookAtPlayers = 1,     // 单人模式 dummy 朝向玩家
        effectsFix = 721,      // 原版强制渲染修复值
    },

    // ---- 命令注册 ----
    commands = {
        "!dance"  = "start",
        "!dancecam" = "start_with_camera",
        "!mytest" = "legacy_start",  // 兼容旧版: Zoey 跳 d01
        "!mystop" = "stop_all",
    },
};

// ==========================================
// 2. MusicController — 副体1: 只管音乐
// ==========================================

MusicController <- {

    activeMusic = [],  // [{ path, entity }]
    _bgmRelay = null,  // 懒加载缓存

    _ensureBgmRelay = function() {
        if(this._bgmRelay == null) {
            this._bgmRelay = Entities.FindByName(null, "logic_branch_bgm_relay");
        }
        return this._bgmRelay;
    },

    precache = function(path) {
        if(!IsSoundPrecached(path)) {
            PrecacheSound(path);
            printl("[Music] 预缓存: %s", path);
        }
    },

    play = function(path, volume, attachEntity) {
        this.precache(path);

        // 关游戏 BGM (如果地图有)
        local relay = this._ensureBgmRelay();
        if(relay != null) {
            EntFire(relay.GetName(), "ToggleTest", 0.0);
            printl("[Music] 暂停 BGM");
        }

        // 参数: (路径, 音量0-10, 传播距离, 衰减系数, 附着实体)
        EmitAmbientSoundOn(path, volume, DanceConfig.music.distance, DanceConfig.music.falloff, attachEntity);

        this.activeMusic.append({ path = path, entity = attachEntity });
        printl("[Music] 开始播放: %s (附着实体: %s)", path, attachEntity.GetName());
    },

    stopAll = function() {
        printl("[Music] === 停止所有音乐 ===");

        foreach(track in this.activeMusic) {
            if(track.entity != null && track.entity.IsValid()) {
                // 参数顺序: (路径, 附着实体) — 原版签名
                StopAmbientSoundOn(track.path, track.entity);
                printl("[Music] 停止: %s", track.path);
            }
        }
        this.activeMusic.clear();

        // 恢复 BGM
        local relay = this._ensureBgmRelay();
        if(relay != null) {
            EntFire(relay.GetName(), "ToggleTest", 0.0);
            printl("[Music] 恢复 BGM");
        }

        // 清除缓存 (下次 FindByName 重查)
        this._bgmRelay = null;
    },
};

// ==========================================
// 3. CameraController — 副体2: 只管相机三件套 + 真人传送
// ==========================================

CameraController <- {

    camProp    = null,  // prop_dynamic (Introcam.mdl)
    viewControl = null, // point_viewcontrol_multiplayer
    savedOrigins = [],  // [{ player, origin }]

    setup = function(spawnPos, angles) {
        printl("[Camera] === 开始 setup ===");

        if(!DanceConfig.camera.enabled) {
            printl("[Camera] 相机在配置里关闭, 跳过");
            return;
        }

        // 3a. Spawn 透明 prop_dynamic (必须用 Introcam.mdl, 原版专用于相机挂接)
        local propName = "dance_cam_" + UniqueString();
        this.camProp = SpawnEntityFromTable("prop_dynamic", {
            targetname = propName,
            model      = DanceConfig.camera.model,
            origin     = spawnPos,
            angles     = angles.ToKVString(),
            rendermode = 10,  // 不可见
            renderamt  = 0,   // 完全透明
        });

        if(this.camProp == null) {
            printl("[Camera] Error: prop_dynamic spawn 失败 (模型不存在? 确认 mdR_Anims_Base 已加载)");
            return;
        }

        // 3b. Spawn point_viewcontrol_multiplayer
        local vcName = "dance_vc_" + UniqueString();
        this.viewControl = SpawnEntityFromTable("point_viewcontrol_multiplayer", {
            targetname = vcName,
            target     = propName,
            parentname = propName,
            origin     = spawnPos,
            angles     = angles.ToKVString(),
            spawnflags = DanceConfig.camera.spawnflags,  // 5 = 启用视角 + 忽略障碍
            fov        = DanceConfig.camera.fov,          // 55 = 电影窄视角
        });

        if(this.viewControl == null) {
            printl("[Camera] Error: view_control spawn 失败");
            return;
        }

        // 3c. 严格按顺序: 挂到 prop 的 "cam" 骨骼 → 激活 viewControl
        EntFire(this.viewControl.GetName(), "SetParent", propName, 0.0);
        EntFire(this.viewControl.GetName(), "SetParentAttachment", "cam", 0.01);
        EntFire(this.viewControl.GetName(), "Enable", "", 0.01);
        printl("[Camera] viewControl 已挂接并启用");

        // 3d. 传送所有真人到 -9999 (bot 排除)
        this.savedOrigins.clear();
        local player = null;
        while(player = Entities.FindByClassname(player, "player")) {
            if(IsPlayerABot(player)) continue;
            this.savedOrigins.append({ player = player, origin = player.GetOrigin() });
            local newOrigin = player.GetOrigin();
            newOrigin.x = newOrigin.x - 9999.0;
            player.SetOrigin(newOrigin);
        }
        printl("[Camera] 已传送 %d 名玩家到虚空", this.savedOrigins.len());
    },

    cleanup = function() {
        printl("[Camera] === 开始 cleanup ===");

        // 3c reverse: 禁用 viewControl
        if(this.viewControl != null) {
            EntFire(this.viewControl.GetName(), "Disable", "", 0.0);
            printl("[Camera] viewControl 已禁用");
        }

        // 3d reverse: 恢复所有玩家位置
        foreach(saved in this.savedOrigins) {
            if(saved.player != null && saved.player.IsValid()) {
                saved.player.SetOrigin(saved.origin);
            }
        }
        this.savedOrigins.clear();
        printl("[Camera] 玩家位置已恢复");

        // 3ab reverse: Kill camProp + viewControl
        if(this.viewControl != null && this.viewControl.IsValid()) {
            this.viewControl.Kill();
            this.viewControl = null;
        }
        if(this.camProp != null && this.camProp.IsValid()) {
            this.camProp.Kill();
            this.camProp = null;
        }
        printl("[Camera] cleanup 完成");
    },
};

// ==========================================
// 4. LyricController — 副体3: 歌词字幕 (占位)
// ==========================================

LyricController <- {

    activeLyrics = [],

    setup = function(actionName, musicPath) {
        // TODO: 未来实现 — SourceMod 菜单 / VScript Panel 显示歌词
        printl("[Lyric] 占位: setup(%s) — 未实现, 跳过", actionName);
    },

    cleanup = function() {
        printl("[Lyric] 占位: cleanup — 无操作");
    },
};

// ==========================================
// 5. DanceController — 主体: 只管 dummy 生命周期
// ==========================================

DanceController <- {

    dummies = [],  // [{ dummy, seqName, duration, musicPath }]

    // ---- 主入口 ----
    start = function(player, modelCode, actionName) {
        printl("[Dance] === start 调用 model=%s action=%s ===", modelCode, actionName);

        // 5a. 查模型路径 (配置表)
        local modelPath = DanceConfig.models[modelCode];
        if(modelPath == null || modelPath == "") {
            printl("[Dance] Error: 未知角色代号 '%s'", modelCode);
            return false;
        }

        // 5b. 查动作配置 (配置表)
        local actionCfg = DanceConfig.actions[actionName];
        if(actionCfg == null) {
            printl("[Dance] Error: 未知动作 '%s' — 请在 DanceConfig.actions 里添加", actionName);
            return false;
        }
        local seqName = actionCfg.seq;
        local musicPath = actionCfg.music;

        // 5c. 射线取瞄准点
        local spawnPos = GetPlayerLookPos(player);
        if(spawnPos == null) {
            printl("[Dance] Error: 射线没有命中任何物体 (瞄准地面再试)");
            return false;
        }

        // 5d. 角度计算: 保留 Pitch/Roll, Yaw+180 面向玩家
        local look_angle = player.GetAngles();
        local reverse_angle = Vector(look_angle.x, look_angle.y + 180, look_angle.z);

        // 5e. [副体2] 先 setup 相机 (如果启用)
        CameraController.setup(spawnPos, reverse_angle);

        // 5f. Spawn dummy (必须用 commentary_dummy, 不能 prop_dynamic)
        local dummy = SpawnEntityFromTable("commentary_dummy", {
            origin     = spawnPos,
            angles     = reverse_angle.ToKVString(),  // 必须转 KV 字符串, 避免 QAngle 静默失败
            model      = modelPath,
            LookAtPlayers = DanceConfig.dummy.lookAtPlayers,
        });

        if(dummy == null) {
            printl("[Dance] Error: commentary_dummy spawn 失败 — 确认模型路径 %s 存在", modelPath);
            CameraController.cleanup();  // 回滚相机 setup
            return false;
        }

        // 5g. 致命守护: sequence 不存在直接删
        local seqId = dummy.LookupSequence(seqName);
        if(seqId == -1) {
            printl("[Dance] Error: Invalid animation sequence '%s' in model %s", seqName, modelPath);
            printl("[Dance] 提示: 如果你替换了角色模型, 原版 d01~d61 sequence 可能丢失");
            dummy.Kill();
            CameraController.cleanup();
            return false;
        }

        // 5h. 渲染修复 (原版神坑, 721 是 EF_NODRAW|EF_NOFLASH 等标志组合)
        NetProps.SetPropInt(dummy, "m_fEffects", DanceConfig.dummy.effectsFix);

        // 5i. 施法! 必须用 EntFire (commentary_dummy.SetAnimation() 不是公开方法)
        EntFire(dummy.GetName(), "SetAnimation", seqName);
        printl("[Dance] EntFire SetAnimation '%s' 已触发", seqName);

        // 5j. [副体1] 播放音乐 (如果启用)
        if(DanceConfig.music.enabled) {
            MusicController.play(musicPath, DanceConfig.music.volume, dummy);
        }

        // 5k. [副体3] 占位: 歌词 setup
        LyricController.setup(actionName, musicPath);

        // 5l. 注册到活跃列表 (精确按 targetname Kill, 不 FindByClassname 杀错)
        local duration = dummy.GetSequenceDuration(seqId);
        local session = {
            dummy     = dummy,
            seqName   = seqName,
            duration  = duration,
            musicPath = musicPath,
        };
        this.dummies.append(session);

        // 5m. 安全定时清理 — 回调存在 dummy ScriptScope 里, RunScriptCode 直接调
        dummy.ValidateScriptScope();
        dummy.GetScriptScope()["_auto_stop"] <- function() {
            ::DanceController._onAutoStop(self);
        };
        DoEntFire(dummy.GetName(), "RunScriptCode", "_auto_stop()", duration, dummy, dummy);
        printl("[Dance] 动画 '%s' 时长 %.2f 秒, 定时器已启动", seqName, duration);

        printl("[Dance] === dummy %s spawn 成功, seq=%s ===", dummy.GetName(), seqName);
        return true;
    },

    // ---- 内部: 定时器触发的自动停止 ----
    _onAutoStop = function(dummy) {
        printl("[Dance] _onAutoStop 触发 (dummy=%s)", dummy != null ? dummy.GetName() : "null");

        // 只清理这个 dummy 对应的 session
        local toRemove = null;
        foreach(i, session in ::DanceController.dummies) {
            if(session.dummy == dummy) { toRemove = i; break; }
        }
        if(toRemove != null) ::DanceController.dummies.remove(toRemove);

        // 如果还有其他 dummy 在跳, 不触发全量 cleanup
        if(::DanceController.dummies.len() > 0) {
            // 只 Kill 这个 dummy
            if(dummy != null && dummy.IsValid()) dummy.Kill();
            printl("[Dance] 还有 %d 个 dummy 活跃, 跳过全量 cleanup", ::DanceController.dummies.len());
        } else {
            // 最后一个 dummy → 全量清理 (副体1+2+3)
            ::DanceController._cleanupAll();
        }
    },

    // ---- 强制停止所有 ----
    stopAll = function() {
        printl("[Dance] === stopAll 强制停止 ===");
        // 手动触发每个 dummy 的 cleanup 逻辑
        foreach(session in this.dummies) {
            if(session.dummy != null && session.dummy.IsValid()) {
                session.dummy.Kill();
            }
        }
        this.dummies.clear();
        this._cleanupAll();
    },

    // ---- 全量清理 (副体1+2+3) ----
    _cleanupAll = function() {
        printl("[Dance] === _cleanupAll ===");
        MusicController.stopAll();
        CameraController.cleanup();
        LyricController.cleanup();
        printl("[Dance] === _cleanupAll 完成 ===");
    },
};

// ==========================================
// 6. 入口: 猴子补丁接管聊天
// ==========================================

function OnGameEvent_player_say(params) {
    local text = ("text" in params) ? params.text : "";
    local player = GetPlayerFromUserID(params.userid);
    if(player == null || !player.IsValid()) return;

    // 按配置表注册的命令分发
    // --- !dance <代号> <动作> ---
    if(text.find("!dance ") == 0) {
        local parts = text.split(" ");
        if(parts.len() < 3) {
            printl("[MyDance] 用法: !dance <角色代号> <动作名>");
            return;
        }
        DanceController.start(player, parts[1].tolower(), parts[2].tolower());
    }
    // --- !dancecam <代号> <动作> (开启相机) ---
    else if(text.find("!dancecam ") == 0) {
        local parts = text.split(" ");
        if(parts.len() < 3) {
            printl("[MyDance] 用法: !dancecam <角色代号> <动作名>");
            return;
        }
        local old = DanceConfig.camera.enabled;
        DanceConfig.camera.enabled = true;
        DanceController.start(player, parts[1].tolower(), parts[2].tolower());
        DanceConfig.camera.enabled = old;
    }
    // --- !mytest (兼容旧版: Zoey 跳 d01) ---
    else if(text == "!mytest") {
        DanceController.start(player, "z", "d01");
    }
    // --- !mystop (强制停止) ---
    else if(text == "!mystop") {
        DanceController.stopAll();
    }
}

// ==========================================
// 7. 初始化打印
// ==========================================

printl("[MyDance] DanceConfig.models 注册 %d 个角色", DanceConfig.models.len());
printl("[MyDance] DanceConfig.actions 注册 %d 个动作 (相机=%s)", DanceConfig.actions.len(), DanceConfig.camera.enabled ? "ON" : "OFF");
