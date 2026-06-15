import numpy as np, laion_clap

_model = _text_emb = _labels = None

def _ensure(taxonomy):
    global _model, _text_emb, _labels
    if _model is not None:
        return
    _model = laion_clap.CLAP_Module(enable_fusion=False)
    _model.load_ckpt()                       # downloads default checkpoint once
    prompts, labels = [], []
    for e in taxonomy:
        for p in e["clap"]:
            prompts.append(p)
            labels.append((e["domain"], e["category"], e["catid"]))
    _text_emb = _model.get_text_embedding(prompts, use_tensor=False)  # L2-normalized
    _labels = labels

def classify(path, taxonomy, threshold):
    _ensure(taxonomy)
    audio_emb = _model.get_audio_embedding_from_filelist([path], use_tensor=False)
    sims = (audio_emb @ _text_emb.T)[0]      # cosine (embeddings are normalized)
    best = int(np.argmax(sims))
    domain, category, catid = _labels[best]
    conf = round(float((sims[best] + 1) / 2), 2)   # map cosine [-1,1] -> [0,1]
    return (domain, category, catid, conf) if conf >= threshold else (None, None, None, conf)
