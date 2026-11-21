#!/usr/bin/env python3
"""Opt-in real OpenZIM 3.4.0 stdio smoke through Hermes v0.23.3 client.

No software is installed here. Pass a real small ZIM directory and installed
bridge. Uses an isolated temporary HERMES_HOME; no model or GPU is required.
This tests MCP transport/discovery/article retrieval, not model tool selection.
"""
import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile

async def smoke(args):
    commit = subprocess.check_output(['git', '-C', str(args.hermes_source), 'rev-parse', 'HEAD'], text=True).strip()
    assert commit == 'caafe5389ae585ef77387a962aee05b1bcf17029', commit
    version = subprocess.check_output([str(args.bridge), '--version'], text=True).strip()
    assert '3.4.0' in version, version
    sys.path.insert(0, str(args.hermes_source))
    from tools import mcp_tool
    assert mcp_tool._ensure_mcp_sdk(), 'Hermes could not load MCP SDK'
    server = mcp_tool.MCPServerTask('openzim')
    config = {'command': str(args.bridge), 'args': [str(args.archive_dir)],
              'sampling': {'enabled': False}, 'connect_timeout': 60}
    try:
        await asyncio.wait_for(server.start(config), timeout=90)
        assert server.session is not None, f'No session: {server._error}'
        listing = await server.session.list_tools()
        names = [tool.name for tool in listing.tools]
        assert 'zim_query' in names, names
        result = await server.session.call_tool('zim_query', {'query': 'tell me about climate change',
                                                             'max_content_length': 1000})
        rendered = result.model_dump_json()
        assert not getattr(result, 'is_error', getattr(result, 'isError', False)), rendered
        assert 'A/Climate_change' in rendered and '## Content' in rendered and 'global warming' in rendered, rendered
        print(json.dumps({'client': 'Hermes v0.23.3 MCPServerTask', 'tools': names,
                          'query': 'tell me about climate change', 'article_found': 'Climate_change',
                          'response_characters': len(rendered), 'bridge_version': version}))
    finally:
        await server.shutdown()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hermes-source', required=True, type=Path)
    parser.add_argument('--bridge', required=True, type=Path)
    parser.add_argument('--archive-dir', required=True, type=Path)
    args = parser.parse_args()
    for key in ('OPENAI_API_KEY', 'OPENROUTER_API_KEY', 'ANTHROPIC_API_KEY', 'NOUS_API_KEY'):
        os.environ.pop(key, None)
    with tempfile.TemporaryDirectory(prefix='hermes-mcp-smoke-') as temp:
        os.environ['HERMES_HOME'] = temp
        asyncio.run(smoke(args))

if __name__ == '__main__': main()
