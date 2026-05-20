"""
Sanitiser for n8n workflow exports before public publication.

Per E18.2-3 (sprint-17). Reads <slug>.json from this dir, writes
<slug>.sanitised.json next to it.

Rules:
- Strip ephemeral workflow metadata (id, versionId, activeVersionId,
  versionCounter, triggerCount, updatedAt, createdAt, isArchived,
  shared, activeVersion, meta.instanceId, meta.templateCredsSetupCompleted)
- Force active=false (importer decides when to activate)
- Empty staticData + pinData (run-specific cached data)
- For each node.credentials.<type>: replace `id` with a placeholder of
  shape "REPLACE_ME_<label-slug>"; keep `name` (the human label, which
  is documentation for the importer)
- Replace internal hostnames + emails in any JSON string value:
    trendai.au          -> example-tenant.com
    taikim.com          -> example-tenant.com
    *@trendai.au        -> *@example-tenant.com
    $SANITISE_OPERATOR_EMAIL -> operator@example-tenant.com
    100.x.x.x tailnet   -> 100.0.0.0 (placeholder)
- Strip n8n-instance-specific webhookId values (n8n regenerates on import)
- Strip errorWorkflow reference (instance-specific)

Output also: <slug>.audit.txt — a human-readable diff summary so the
reviewer can confirm what was scrubbed.
"""

import json
import os
import re
import sys

PENDING = os.path.dirname(os.path.abspath(__file__))

# Patterns to redact in string values
HOST_PATTERNS = [
    (re.compile(r'\b(?:[a-z0-9-]+\.)*trendai\.au\b'), 'example-tenant.com'),
    (re.compile(r'\b(?:[a-z0-9-]+\.)*taikim\.com\b'), 'example-tenant.com'),
    (re.compile(r'\btrendmedia\.au\b'), 'example-tenant.com'),
    (re.compile(r'\bhappyhome\.au\b'), 'example-tenant.com'),
    (re.compile(r'\bmaxlearn\.au\b'), 'example-tenant.com'),
]
EMAIL_PATTERNS = [
    # The operator's own address is NOT hard-coded: this file is public and
    # a scrubber that names the person it scrubs defeats itself. Set
    # SANITISE_OPERATOR_EMAIL to have your own address redacted too.
    *([(re.compile(re.escape(os.environ['SANITISE_OPERATOR_EMAIL'])),
       'operator@example-tenant.com')]
      if os.environ.get('SANITISE_OPERATOR_EMAIL') else []),
    (re.compile(r'[a-zA-Z0-9._%+-]+@trendai\.au'), 'noreply@example-tenant.com'),
    (re.compile(r'[a-zA-Z0-9._%+-]+@taikim\.com'), 'noreply@example-tenant.com'),
    (re.compile(r'[a-zA-Z0-9._%+-]+@happyhome\.au'), 'noreply@example-tenant.com'),
    (re.compile(r'[a-zA-Z0-9._%+-]+@maxlearn\.au'), 'noreply@example-tenant.com'),
    (re.compile(r'[a-zA-Z0-9._%+-]+@trendmedia\.au'), 'noreply@example-tenant.com'),
]
TAILSCALE = re.compile(r'\b100\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')


# Same reasoning as the email rule above. SANITISE_OPERATOR_HANDLE is a
# regex alternation, e.g. 'jdoe|john\\s+doe'. Unset, this matches nothing
# rather than matching everything — a scrubber that silently stops
# scrubbing is worse than one that visibly does not run.
_handle = os.environ.get('SANITISE_OPERATOR_HANDLE', '')
PERSONAL_NAME = re.compile(r'\b(?:' + _handle + r')\b', re.I) if _handle \
    else re.compile(r'(?!x)x')


def slugify(label):
    # Strip personal identifiers before slugging — they'd otherwise
    # ride along inside the REPLACE_ME_<slug> placeholder.
    cleaned = PERSONAL_NAME.sub('', label or 'unknown')
    s = re.sub(r'[^a-zA-Z0-9]+', '-', cleaned).strip('-').lower()
    return s or 'unknown'


def scrub_cred_label(label):
    """Scrub personal identifiers from a credential's human label too."""
    if not isinstance(label, str):
        return label
    out = PERSONAL_NAME.sub('', label).strip(' -')
    # Collapse multiple separators
    out = re.sub(r'\s+-\s+', ' - ', out)
    out = re.sub(r'-{2,}', '-', out)
    return out


def redact_string(s):
    """Redact a single string value."""
    if not isinstance(s, str):
        return s
    out = s
    for rx, sub in HOST_PATTERNS:
        out = rx.sub(sub, out)
    for rx, sub in EMAIL_PATTERNS:
        out = rx.sub(sub, out)
    out = TAILSCALE.sub('100.0.0.0', out)
    return out


def walk_redact(obj):
    """Recursively redact string values inside a nested structure."""
    if isinstance(obj, dict):
        return {k: walk_redact(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [walk_redact(x) for x in obj]
    if isinstance(obj, str):
        return redact_string(obj)
    return obj


def sanitise(workflow):
    """Sanitise one workflow dict in place + return audit notes."""
    audit = []

    # Drop ephemeral / instance-specific top-level keys.
    for k in [
        'id', 'versionId', 'activeVersionId', 'versionCounter',
        'triggerCount', 'updatedAt', 'createdAt', 'isArchived',
        'shared', 'activeVersion',
    ]:
        if k in workflow:
            audit.append(f"  dropped top-level: {k}")
            del workflow[k]

    # Reset active flag — importer decides
    if workflow.get('active'):
        audit.append("  reset active: true -> false")
    workflow['active'] = False

    # Empty staticData + pinData
    if workflow.get('staticData'):
        audit.append("  emptied staticData")
    workflow['staticData'] = None
    if workflow.get('pinData'):
        audit.append("  emptied pinData")
    workflow['pinData'] = {}

    # Strip meta.instanceId / templateCredsSetupCompleted if present
    meta = workflow.get('meta')
    if isinstance(meta, dict):
        for mk in ('instanceId', 'templateCredsSetupCompleted'):
            if mk in meta:
                audit.append(f"  dropped meta.{mk}")
                del meta[mk]

    # Strip errorWorkflow + ensure executionOrder stays
    settings = workflow.get('settings', {})
    if isinstance(settings, dict) and 'errorWorkflow' in settings:
        audit.append(f"  dropped settings.errorWorkflow ({settings['errorWorkflow']})")
        del settings['errorWorkflow']

    # Per-node sanitisation
    for node in workflow.get('nodes', []):
        # Strip webhookId (instance-specific, n8n regenerates)
        if 'webhookId' in node:
            audit.append(f"  node '{node.get('name','?')}' -- dropped webhookId")
            del node['webhookId']

        # Credentials: replace id with placeholder + scrub human label
        creds = node.get('credentials', {})
        for ctype, cval in creds.items():
            if isinstance(cval, dict) and 'id' in cval:
                label = cval.get('name', ctype)
                placeholder = f"REPLACE_ME_{slugify(label)}"
                old = cval['id']
                cval['id'] = placeholder
                audit.append(f"  node '{node.get('name','?')}' -- cred.{ctype}.id: {old} -> {placeholder}")
                # Also scrub the human label
                if 'name' in cval:
                    new_name = scrub_cred_label(cval['name'])
                    if new_name != cval['name']:
                        audit.append(f"  node '{node.get('name','?')}' -- cred.{ctype}.name: {cval['name']!r} -> {new_name!r}")
                        cval['name'] = new_name

    # Recursively redact host/email/IP patterns in all string values
    sanitised = walk_redact(workflow)
    workflow.clear()
    workflow.update(sanitised)

    return audit


def main():
    import glob
    for src in sorted(glob.glob(os.path.join(PENDING, '*.json'))):
        if '.sanitised' in src or src.endswith('audit.json'):
            continue
        with open(src, 'r', encoding='utf-8') as f:
            wf = json.load(f)
        audit = sanitise(wf)
        dst = src.replace('.json', '.sanitised.json')
        with open(dst, 'w', encoding='utf-8') as f:
            json.dump(wf, f, indent=2, ensure_ascii=False)
        audit_path = src.replace('.json', '.audit.txt')
        with open(audit_path, 'w', encoding='utf-8') as f:
            f.write(f"# Sanitisation audit for {os.path.basename(src)}\n\n")
            f.write("\n".join(audit))
            f.write("\n")
        print(f"\n=== {os.path.basename(src)} ===")
        for line in audit:
            print(line)


if __name__ == '__main__':
    main()
