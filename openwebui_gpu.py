"""Strict OpenVINO B580 selection for Open WebUI's native retrieval backends.

No AUTO/HETERO/CPU fallback. This helper does not change drivers or configuration.
"""
import argparse
import json
import os
import re

BACKENDS = ('SENTENCE_TRANSFORMERS_BACKEND', 'SENTENCE_TRANSFORMERS_CROSS_ENCODER_BACKEND')
KWARGS = ('SENTENCE_TRANSFORMERS_MODEL_KWARGS', 'SENTENCE_TRANSFORMERS_CROSS_ENCODER_MODEL_KWARGS')
TRUST = ('RAG_EMBEDDING_MODEL_TRUST_REMOTE_CODE', 'RAG_RERANKING_MODEL_TRUST_REMOTE_CODE')


def select_b580(core):
    devices = []
    for device in core.available_devices:
        if not re.fullmatch(r'GPU(?:\.\d+)?', device):
            continue
        name = str(core.get_property(device, 'FULL_DEVICE_NAME'))
        if re.search(r'\bB580\b', name, re.I):
            devices.append(device)
    if len(devices) != 1:
        raise RuntimeError('Expected exactly one OpenVINO-visible Intel Arc B580 GPU; found '
                           + str(len(devices)) + '. Check the Intel GPU driver. No CPU fallback was selected.')
    return devices[0]


def environment(core):
    device = select_b580(core)
    result = {key: 'openvino' for key in BACKENDS}
    result.update({key: json.dumps({'device': device}, separators=(',', ':')) for key in KWARGS})
    result.update(USE_CUDA_DOCKER='false', USE_SLIM_DOCKER='false')
    result.update({key: 'false' for key in TRUST})
    return result


def verify(core, env):
    device = select_b580(core)
    for key in BACKENDS:
        if env.get(key) != 'openvino':
            raise RuntimeError(key + ' must explicitly be openvino; configuration was not changed.')
    for key in KWARGS:
        try:
            value = json.loads(env.get(key, ''))
        except (TypeError, ValueError) as exc:
            raise RuntimeError(key + ' must contain explicit OpenVINO GPU configuration') from exc
        if not isinstance(value, dict) or value.get('device') != device:
            raise RuntimeError(key + ' must target the currently detected B580 device ' + device
                               + '; no automatic device reassignment or CPU fallback was performed.')
    if env.get('USE_SLIM_DOCKER', '').lower() != 'false' or env.get('USE_CUDA_DOCKER', '').lower() != 'false':
        raise RuntimeError('Intel retrieval requires explicit non-slim OpenVINO configuration, not CUDA.')
    if any(env.get(key, '').lower() != 'false' for key in TRUST):
        raise RuntimeError('Retrieval remote code must be disabled; custom model compatibility requires review.')
    return device


def assert_execution(model, device):
    native = getattr(model, 'transformers_model', None)
    request = getattr(native, 'request', None)
    if request is None:
        raise RuntimeError('OpenVINO model did not expose a compiled request after inference')
    actual = list(request.get_property('EXECUTION_DEVICES'))
    # Explicit GPU aliases can normalize to GPU.0. Never accept CPU/AUTO or a
    # different discrete device. The Core selection already verified B580 identity.
    allowed = {device, 'GPU.0'} if device == 'GPU' else {device}
    if not actual or any(str(item) not in allowed for item in actual):
        raise RuntimeError('Unexpected OpenVINO execution devices: ' + repr(actual)
                           + '; expected only ' + device)


def probe(core, env, embedding_model, reranking_model, loaders=None):
    device = verify(core, env)
    if not embedding_model or not reranking_model:
        raise RuntimeError('Both explicit embedding and reranking model IDs are required for the GPU probe')
    if loaders is None:
        # This is the same native released WebUI construction path, including
        # SentenceTransformer device/backend/model_kwargs, not a separate engine.
        from open_webui.routers.retrieval import get_ef, get_rf
        loaders = (get_ef, get_rf)
    embedding = loaders[0]('', embedding_model)
    if embedding is None:
        raise RuntimeError('Native Open WebUI failed to load the embedding model; no fallback accepted')
    embedding.encode(['GPU validation document'])
    assert_execution(embedding, device)
    del embedding
    reranker = loaders[1]('', reranking_model)
    if reranker is None:
        raise RuntimeError('Native Open WebUI failed to load the reranker; no fallback accepted')
    reranker.predict([('validation query', 'GPU validation document')])
    assert_execution(reranker, device)
    return device


def probe_cuda(embedding_model, reranking_model):
    import torch
    from open_webui.env import DEVICE_TYPE, USE_SLIM
    from open_webui.routers.retrieval import get_ef, get_rf
    if not torch.cuda.is_available() or DEVICE_TYPE != 'cuda' or USE_SLIM:
        raise RuntimeError('Native Open WebUI CUDA is unavailable; no CPU fallback accepted')
    for model, method, values in (
        (get_ef('', embedding_model), 'encode', ['GPU validation document']),
        (get_rf('', reranking_model), 'predict', [('validation query', 'GPU validation document')]),
    ):
        if model is None or getattr(getattr(model, 'device', None), 'type', None) != 'cuda':
            raise RuntimeError('Native retrieval model is not on CUDA')
        output = getattr(model, method)(values, convert_to_tensor=True)
        if not getattr(output, 'is_cuda', False):
            raise RuntimeError('Native retrieval inference did not return a CUDA tensor')
    print('Verified native Open WebUI embedding and reranking inference on CUDA')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['detect-openvino', 'verify-openvino', 'probe-openvino', 'probe-cuda'])
    parser.add_argument('--embedding-model')
    parser.add_argument('--reranking-model')
    args = parser.parse_args()
    if args.action == 'probe-cuda':
        if not args.embedding_model or not args.reranking_model:
            parser.error('Both model IDs are required')
        probe_cuda(args.embedding_model, args.reranking_model)
        return
    from openvino import Core
    core = Core()
    if args.action == 'detect-openvino':
        print(json.dumps(environment(core)))
    elif args.action == 'probe-openvino':
        device = probe(core, os.environ, args.embedding_model, args.reranking_model)
        print('Verified native Open WebUI embedding and reranking inference on ' + device)
    else:
        print('Verified OpenVINO-visible B580 device: ' + verify(core, os.environ)
              + '. Model inference verification is a separate check.')


if __name__ == '__main__':
    main()
