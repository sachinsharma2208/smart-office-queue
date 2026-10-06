#!/usr/bin/env python3
"""End-to-end smoke test for a RUNNING backend (python3 stdlib only).

    SEED_PASSWORD='Demo@12345' python3 scripts/smoke_test.py [http://localhost:8080]

Exercises the real HTTP API + PostgreSQL: auth, FIFO, priority, no-show,
cancel, transfer, pause/resume, authorization and the dashboard.
Run it against a fresh database (it creates tokens).
"""
import json, os, sys, urllib.request, urllib.error

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080").rstrip("/")
PASSWORD = os.environ.get("SEED_PASSWORD", "Demo@12345")
passed = failed = 0


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or "null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "null")


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name} {extra}")


def login(email):
    st, body = call("POST", "/api/auth/login", {"email": email, "password": PASSWORD})
    assert st == 200, f"login {email} failed: {st} {body}"
    return body["token"]


def err_code(body):
    return (body or {}).get("error", {}).get("code")


print("== auth")
st, body = call("POST", "/api/auth/login", {"email": "admin@smartoffice.local", "password": "wrong"})
check("wrong password -> 401", st == 401 and err_code(body) == "unauthorized")
admin = login("admin@smartoffice.local")
it_staff = login("it.staff@smartoffice.local")
hr_staff = login("hr.staff@smartoffice.local")
st, _ = call("POST", "/api/queues/00000000-0000-0000-0000-000000000000/call-next")
check("staff endpoint without token -> 401", st == 401)

st, depts = call("GET", "/api/departments")
check("4 departments in order", [d["code"] for d in depts] == ["IT", "HR", "ACC", "ADM"], str(depts))
D = {d["code"]: d["id"] for d in depts}

print("== token numbering, FIFO, priority")
def new(code, prio="NORMAL"):
    st, t = call("POST", "/api/tokens", {"department_id": D[code], "priority": prio})
    assert st == 201, (st, t)
    return t

t1, t2, t3 = new("IT"), new("IT"), new("IT")
check("numbers IT-001..003", [t1["token_number"], t2["token_number"], t3["token_number"]] == ["IT-001", "IT-002", "IT-003"])
check("HR numbering independent", new("HR")["token_number"] == "HR-001")
check("position/ETA of IT-003", t3["queue_position"] == 3 and t3["estimated_wait_minutes"] == 10, str(t3))

st, called = call("POST", f"/api/queues/{D['IT']}/call-next", token=it_staff)
check("call next -> IT-001 SERVING", st == 200 and called["token_number"] == "IT-001" and called["status"] == "SERVING")
st, body = call("POST", f"/api/queues/{D['IT']}/call-next", token=it_staff)
check("call next while serving -> 409", st == 409 and err_code(body) == "serving_in_progress")

t4 = new("IT", "PRIORITY")
check("priority token position 1", t4["queue_position"] == 1 and t4["priority"] == "PRIORITY")
st, cur = call("GET", f"/api/tokens/{t1['id']}")
check("priority did not interrupt serving token", cur["status"] == "SERVING")
st, done = call("POST", f"/api/tokens/{t1['id']}/complete", token=it_staff)
check("complete IT-001", st == 200 and done["status"] == "COMPLETED" and done["completed_at"])
st, body = call("POST", f"/api/tokens/{t1['id']}/complete", token=it_staff)
check("complete twice -> 409", st == 409 and err_code(body) == "token_completed")
st, body = call("DELETE", f"/api/tokens/{t1['id']}")
check("cancel completed token -> 409", st == 409 and err_code(body) == "token_completed")

st, called = call("POST", f"/api/queues/{D['IT']}/call-next", token=it_staff)
check("priority IT-004 called before IT-002/003", called["token_number"] == "IT-004")

print("== no-show")
st, ns = call("POST", f"/api/tokens/{t4['id']}/no-show", token=it_staff)
check("1st no-show: WAITING, count 1, priority dropped", st == 200 and ns["status"] == "WAITING" and ns["no_show_count"] == 1 and ns["priority"] == "NORMAL", str(ns))
st, q = call("GET", f"/api/queues/{D['IT']}")
order = [t["token_number"] for t in q["waiting"]]
check("1st no-show: token moved to the very end", order == ["IT-002", "IT-003", "IT-004"], str(order))
for expected in ("IT-002", "IT-003"):
    st, called = call("POST", f"/api/queues/{D['IT']}/call-next", token=it_staff)
    check(f"call next -> {expected}", called["token_number"] == expected)
    call("POST", f"/api/tokens/{called['id']}/complete", token=it_staff)
st, called = call("POST", f"/api/queues/{D['IT']}/call-next", token=it_staff)
check("IT-004 called again", called["token_number"] == "IT-004")
st, ns = call("POST", f"/api/tokens/{t4['id']}/no-show", token=it_staff)
check("2nd no-show: CANCELLED, count 2", ns["status"] == "CANCELLED" and ns["no_show_count"] == 2, str(ns))
st, body = call("POST", f"/api/queues/{D['IT']}/call-next", token=it_staff)
check("cancelled token never called again (queue empty)", st == 404 and err_code(body) == "queue_empty")

print("== cancel + transfer + pause")
t3 = new("IT")  # fresh tokens for the remaining scenarios
t2 = new("IT")
st, c = call("DELETE", f"/api/tokens/{t3['id']}")
check("visitor cancels waiting token", st == 200 and c["status"] == "CANCELLED")
st, body = call("POST", f"/api/tokens/{t3['id']}/cancel")
check("cancel twice -> 409", st == 409 and err_code(body) == "token_cancelled")
st, body = call("GET", "/api/tokens/not-a-uuid")
check("invalid id -> 400", st == 400 and err_code(body) == "validation_error")
st, body = call("GET", "/api/tokens/00000000-0000-4000-8000-000000000000")
check("unknown id -> 404", st == 404)

st, body = call("POST", f"/api/tokens/{t2['id']}/transfer", {"target_department_id": D["HR"]}, token=hr_staff)
check("HR staff cannot transfer an IT token -> 403", st == 403)
st, body = call("POST", f"/api/tokens/{t2['id']}/transfer", {"target_department_id": D["IT"]}, token=it_staff)
check("transfer to same dept -> 400", st == 400 and err_code(body) == "invalid_transfer")

st, pa = call("POST", f"/api/departments/{D['HR']}/pause", token=it_staff)
check("staff cannot pause -> 403", st == 403)
st, pa = call("POST", f"/api/departments/{D['HR']}/pause", token=admin)
check("admin pauses HR", st == 200 and pa["is_paused"] is True)
st, body = call("POST", "/api/tokens", {"department_id": D["HR"]})
check("paused dept rejects new token -> 409", st == 409 and err_code(body) == "department_paused")
st, body = call("POST", f"/api/tokens/{t2['id']}/transfer", {"target_department_id": D["HR"]}, token=it_staff)
check("transfer into paused dept -> 409", st == 409 and err_code(body) == "department_paused")
st, hr_q = call("GET", f"/api/queues/{D['HR']}")
check("existing HR token stays queued while paused", len(hr_q["waiting"]) == 1)
st, re = call("POST", f"/api/departments/{D['HR']}/resume", token=admin)
check("admin resumes HR", st == 200 and re["is_paused"] is False)

st, tr = call("POST", f"/api/tokens/{t2['id']}/transfer", {"target_department_id": D["HR"]}, token=it_staff)
check("transfer IT-002 -> HR-002", st == 200 and tr["new_token"]["token_number"] == "HR-002" and tr["old_token"]["status"] == "TRANSFERRED", str(tr))
check("new token links to original", tr["new_token"]["transferred_from_token_id"] == t2["id"])
st, old = call("GET", f"/api/tokens/{t2['id']}")
check("old token points to new one + history", old["transferred_to_token_number"] == "HR-002" and len(old["events"]) >= 2)

print("== dashboard")
st, body = call("GET", "/api/dashboard", token=it_staff)
check("dashboard is admin-only -> 403", st == 403)
st, dash = call("GET", "/api/dashboard", token=admin)
check("admin dashboard totals", st == 200 and dash["totals"]["completed"] == 3 and dash["totals"]["no_shows"] == 2 and dash["totals"]["total_departments"] == 4, str(dash["totals"]))
st, body = call("GET", f"/api/dashboard/{D['HR']}", token=it_staff)
check("staff cannot see other department dashboard -> 403", st == 403)
st, body = call("GET", f"/api/dashboard/{D['IT']}", token=it_staff)
check("staff sees own department dashboard", st == 200 and body["department_code"] == "IT")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
