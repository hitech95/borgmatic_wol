# borgmatic WoL

A small container image that adds Wake-on-LAN and SSH shutdown hooks to
borgmatic. If the target server is already online, it is left running.

## Configure

Set the target details in `docker-compose.yml` (or your container environment):

- `BORG_WOL_HOST`: address used to check whether the server is online.
- `BORG_WOL_MAC`: target NIC's MAC address.
- `BORG_WOL_CHECK_PORT`: optional TCP port to probe instead of ping (for example, `22`).
- `BORG_WOL_SSH_USER`: SSH user allowed to shut down the target.

The container needs host networking to send the WoL packet on the local network.
Mount an SSH key into `/root/.ssh` and make sure the target accepts it for
passwordless SSH shutdown.

Add these hooks to your borgmatic configuration:

```yaml
before_everything:
  - /usr/local/bin/borgmatic-wol-hook.sh wake
after_everything:
  - /usr/local/bin/borgmatic-wol-hook.sh shutdown
```

The hook remembers whether it woke the target in `/tmp/borgmatic-wol.state`.
For overlapping or multiple target runs, set `BORG_WOL_STATE_FILE` to a
different path for each run.

## Run

Edit `docker-compose.yml` with your configuration, then start the container:

```sh
docker compose up -d
```

The image is published at
[`ghcr.io/hitech95/borgmatic_wol`](https://github.com/hitech95/borgmatic_wol/pkgs/container/borgmatic_wol).
To build it locally instead:

```sh
docker build -t borgmatic-wol .
```

See `borgmatic-wol-hook.sh --help` for all supported environment variables.

## License

[MIT](LICENSE)
