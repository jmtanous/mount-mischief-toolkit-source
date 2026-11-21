#!/usr/bin/env python3
"""SD-only Pilot bootstrap for Benro systems without localhost resolution.

Upstream source/config remain unchanged. Only the two internal browser-proxy
resource constructors receive numeric IPv4 loopback URLs. No global resolver
override, firmware change, or controller connection is performed here.
"""
import argparse
from pathlib import Path
import runpy
import sys
from urllib.parse import urlsplit, urlunsplit


def numeric_loopback(url):
    parts = urlsplit(url)
    if parts.scheme not in ('http', 'https', 'ws', 'wss') or parts.hostname != 'localhost':
        return url
    if parts.username is not None or parts.password is not None:
        raise ValueError('Unexpected credentials in internal Pilot proxy URL')
    authority = '127.0.0.1' + (f':{parts.port}' if parts.port is not None else '')
    return urlunsplit(parts._replace(netloc=authority))


def install_proxy_compat(module):
    class NativeRestProxy(module.AlpacaProxyResource):
        def __init__(self, api_base):
            super().__init__(numeric_loopback(api_base))

    class NativeSocketProxy(module.AlpacaSocketProxyResource):
        def __init__(self, socket_base):
            super().__init__(numeric_loopback(socket_base))

    module.AlpacaProxyResource = NativeRestProxy
    module.AlpacaSocketProxyResource = NativeSocketProxy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('/app/sd/opt/alpaca-pilot-2.2'))
    parser.add_argument('--listen', choices=('127.0.0.1', '0.0.0.0'), default='127.0.0.1')
    args = parser.parse_args()
    driver = args.app.resolve()/'driver'
    sys.path.insert(0, str(driver))
    from config import Config
    import app_web
    original_load = Config.load

    def native_load(*load_args, **load_kwargs):
        original_load(*load_args, **load_kwargs)
        # The bootstrap exposes software services only. Deliberate subsequent
        # connection uses Pilot's normal ConfigUpdate/ConnectPolaris APIs.
        assert Config.polaris_ip_address == '127.0.0.1' and Config.polaris_port == 19090
        assert not Config.polaris_auto_retry and not Config.restore_tracking_on_restart
        Config.apply_changes({'alpaca_restapi_ip_address': args.listen})

    Config.load = native_load
    install_proxy_compat(app_web)
    # Do not pass bootstrap-only switches to any upstream argument processing.
    sys.argv = [str(driver/'main.py')]
    runpy.run_path(str(driver/'main.py'), run_name='__main__')


if __name__ == '__main__':
    main()
