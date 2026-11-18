"""Disposable CI only: real approved retrieval models on CPU OpenVINO.

Not user GPU configuration. No repository model code execution is enabled.
The revision guard prevents silently testing changed upstream artifacts.
"""
from huggingface_hub import HfApi
from sentence_transformers import SentenceTransformer, CrossEncoder

MODELS = [
 ('BAAI/bge-small-en-v1.5', '5c38ec7c405ec4b44b94cc5a9bb96e735b38267a'),
 ('cross-encoder/ms-marco-MiniLM-L6-v2', '233902d25c440f23af6f7d6e94d2946bac0bee0a'),
]
for model, revision in MODELS:
 if HfApi().model_info(model).sha != revision:
  raise RuntimeError('Audited model revision changed; review before updating fixture: ' + model)
embedding = SentenceTransformer(MODELS[0][0], backend='openvino', model_kwargs={'device':'CPU'}, trust_remote_code=False)
result = embedding.encode(['retrieval fixture'])
assert result.shape == (1,384), result.shape
assert list(embedding.transformers_model.request.get_property('EXECUTION_DEVICES')) == ['CPU']
reranker = CrossEncoder(MODELS[1][0], backend='openvino', model_kwargs={'device':'CPU'}, trust_remote_code=False)
assert len(reranker.predict([('query','document')])) == 1
assert list(reranker.transformers_model.request.get_property('EXECUTION_DEVICES')) == ['CPU']
print('Real BGE embedding and MiniLM reranker CPU OpenVINO fixture passed; not a GPU test.')
