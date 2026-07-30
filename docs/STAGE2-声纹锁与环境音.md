# 第二阶段:声纹锁 + 环境音识别

第一阶段(转写 + 语气)已上线。这一阶段给 ears 再加两只耳朵,**代码早就写好在
`earsplus.py` 里**,只是模型没下、`onnxruntime` 没装。本阶段把它们接上。

## 加了什么

| 能力 | 作用 | 模型 |
|---|---|---|
| **声纹锁** | 只有主人的声音会被转写上云;别人说话只记「有人说话了」,内容不转写不上传——是隐私保护 | ECAPA-TDNN(~80MB) |
| **环境音** | 认出雨声/猫叫/门铃/键盘等 521 类声音,附在记录里 | YAMNet(~15MB) |

模型来源(免鉴权,构建时联网下载):
- YAMNet:`huggingface.co/zeropointnine/yamnet-onnx`(`yamnet.onnx` + `yamnet_class_map.csv`)
- ECAPA:`huggingface.co/losfen/spkrec-ecapa-voxceleb-onnx`(`embedding_model.onnx` → 存为 `ecapa.onnx`)

## 怎么部署(在第一阶段镜像基础上)

一个构建开关,不改任何业务代码:

```bash
# 1. 本地构建带模型的镜像(比第一阶段多 ~95MB + 下载时间)
docker build --build-arg WITH_ONNX=1 -t crossandarisu/ears:v0.3-onnx .

# 2. 推到 Docker Hub
docker push crossandarisu/ears:v0.3-onnx

# 3. 把 ears2 服务切到新 tag(不改仓库名)——用 GraphQL,重启即生效
#    updateServiceImageTag(serviceID, environmentID, tag:"v0.3-onnx") 然后 service restart
```

**不加 `--build-arg WITH_ONNX=1` 就是第一阶段镜像**,两者同出一个 Dockerfile。

## 上线后的行为

- **需要重新学声纹**:声纹锁认的是声带特征,和第一阶段的「音量/语速基线」是两套东西。
  开启后前 **6 段合格录音**(每段 ≥2 秒)自动注册成主人的声纹,期间一律放行、
  返回「学习中」。所以刚上线那几条不会拦人,正常发几条就毕业。
- **环境音**:装了模型即刻生效,无需注册。语音类不当环境声报(转写已经在管人声)。
- **阈值**:`SIM_THRESHOLD=0.35`(保守起步)。若主人的声音偶尔被判成「陌生声音」,
  说明阈值偏高,调低;若别人也被放进来,调高。改 `earsplus.py` 顶部常量。
- **家庭成员声纹**:`POST /api/earsplus/enroll {"name":"妈妈"}` 开始给某人注册
  (接下来 6 段归此人),`{"name":""}` 取消。认人但不记该人说话内容。

## 已验证(2026-07-26 写这份时)

- 两个模型下载地址可用、免鉴权;体积 ECAPA 79.6MB / YAMNet 15.3MB / CSV 极小。
- **模型签名与代码假设逐一核对通过**:ECAPA 输入 `feats[batch,frames,80]`+`wav_lens[batch]`、
  输出 `embedding[batch,192]`,与 `_mfcc_vec` 的喂法一致;YAMNet 输入 1 维波形、
  输出 `[帧,521]`,走 `env_sounds` 的「说话间隙检测」分支,521 类与 CSV 行数对上。
- `ecapa_preprocess.json` 只是注释里的参考,预处理参数已硬编码在代码里,运行时不需要它。
- **尚未做**:带 `WITH_ONNX=1` 的完整镜像构建 + 真实语音端到端(栖栖要求本阶段只写不部署)。
  部署前建议先本地 `docker build --build-arg WITH_ONNX=1 .` 跑通(Dockerfile 里已加
  构建期模型加载自检),再推 Docker Hub。
