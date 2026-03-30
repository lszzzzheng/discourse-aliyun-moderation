# discourse-aliyun-moderation

Standalone Discourse plugin for Aliyun moderation.

This plugin intercepts:
- topic and reply creation
- signup/profile text updates
- avatar updates

It calls an external moderation gateway and applies `PASS`, `REVIEW`, or `REJECT`.

## Requirements

- Discourse 3.2+
- A reachable moderation gateway endpoint

## Site Settings

After installation, go to `Admin -> Settings -> Plugins` and search `aliyun moderation`.

- `aliyun_moderation_enabled`
- `aliyun_moderation_profile_enabled`
- `aliyun_moderation_gateway_url`
- `aliyun_moderation_timeout_ms`
- `aliyun_moderation_fail_safe_mode`
- `aliyun_moderation_include_context_posts`

## Install In app.yml

Recommended: pin the plugin to a tag or commit instead of tracking `main`.

Example using a tag:

```yml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - rm -rf discourse-aliyun-moderation
          - git clone https://github.com/lszzzzheng/discourse-aliyun-moderation.git
          - cd discourse-aliyun-moderation && git checkout v1.0.0
```

Example using a commit:

```yml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - rm -rf discourse-aliyun-moderation
          - git clone https://github.com/lszzzzheng/discourse-aliyun-moderation.git
          - cd discourse-aliyun-moderation && git checkout <commit-sha>
```

Then rebuild:

```bash
cd /var/discourse
./launcher rebuild app
```

## Behavior

- `PASS`: allow publish/save
- `REVIEW`: queue post or block profile/avatar save with review message
- `REJECT`: block publish/save immediately
- gateway failure: defaults to review unless fail-safe is switched to pass

## Quick Verification

1. Enable `aliyun_moderation_enabled = true`
2. Enable `aliyun_moderation_profile_enabled = true`
3. Post a normal topic and confirm it publishes
4. Update nickname with risky text and confirm it is blocked
5. Upload a risky avatar and confirm it is blocked
