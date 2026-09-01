# Protótipos de pesquisa (Python)

Scripts usados pra fazer a engenharia reversa e provar o protocolo no controle real.
**Não são o app** — são a referência executável do que está documentado em `docs/protocol.md`.

```bash
python3 -m venv .venv && .venv/bin/pip install hidapi pyusb pillow
brew install libusb hidapi

.venv/bin/python probe.py                      # enumera USB/HID do controle
.venv/bin/python apex4.py info|led ...         # modo DInput, sem root
sudo .venv/bin/python sudo_screen.py foo.gif --go   # modo XInput, tela (root)
sudo .venv/bin/python sudo_screen.py led brightness 30  # modo XInput, LED + salvar na flash
```

`sudo_screen.py led …` executa `xinput_led.py` (subcomando, pra caber numa única regra de sudoers).
