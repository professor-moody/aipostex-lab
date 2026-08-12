SPEAKER SCRIPT
Hunting Shadow AI
Capital One Cyber Resilience  ·  30-minute briefing  ·  15 slides plus 2 backup
PREPARED BY   Keys  ·  Halo Forge Labs
RUNS   approximately 25:30 of content in a 30-minute slot
PACE   written for roughly 140 words per minute, measured delivery
How to read this script
Black text is spoken — read it aloud at a measured pace. Gray italic text in brackets is a stage direction — what is on screen, when to advance, what to point at. It is not spoken.
In the demo sections, RUN marks a command to type, SAY marks spoken lines, POINT marks what to highlight in the output, and IF IT BREAKS is the fallback. Times are budgets; the running clock lets you check pace against a watch.
Timing overview
	SEGMENT	BUDGET	RUNNING CLOCK
1	Cover	0:30	0:30
2	Briefing map — one story, three proof paths	0:45	1:15
3	Adoption and the visible surface	1:30	2:45
4	Shodan exhibit	1:00	3:45
5	Threat convergence	2:00	5:45
6	AI-native surfaces — MCP and RAG	1:15	7:00
7	Lab topology	1:30	8:30
8	Twelve scenarios, three tracks	1:00	9:30
9	Demo menu	0:45	10:15
10	Demo A — Shadow AI map (live)	3:00	13:15
11	Demo B — Notebook secret to gateway (live)	3:45	17:00
12	Demo C — ML platform credential chain (live)	4:15	21:15
13	Product proof	1:30	22:45
14	Defender actions	2:00	24:45
15	Close	0:45	25:30
	Content total	25:30
	Questions and buffer	4:30
	Full slot	30:00

The script
Slide 1   Cover
0:30 budget      running clock 0:30
[ Title slide up. Wait for the room to settle, then open. ]
Thank you. Over the next half hour I want to make a single argument, and back it three different ways. The argument is the line on the screen. Shadow AI is unmanaged infrastructure. It is not mainly about employees pasting data into a chatbot. It is inference servers, vector databases, and agent gateways that real teams stood up to do real work, and that no central system ever inventoried. I will show you a lab that reproduces that, three live demonstrations against it, and the open-source tooling we built in response.
Slide 2   Briefing map — one story, three proof paths
0:45 budget      running clock 1:15
[ Advance to slide 2. Three numbered proof paths. ]
Here is the shape of the next thirty minutes. One story, three proof paths. The first path is the lab — a five-VM range that reproduces shadow AI sprawl the way it actually forms inside a company. Native installs, four independent teams, twenty-nine AI and ML endpoints on one subnet. The second path is the demonstrations — three flows I will run live against that lab. The third is the tool itself: aipostex, open-source offensive tooling that reads these services for meaning and exploit primitives, not just for open ports. Everything after this slide is evidence for that one claim. Let us start with why the claim matters.
Slide 3   Adoption and the visible surface
1:30 budget      running clock 2:45
[ Advance to slide 3. Left: the growth curve. Right: the public surface. ]
Start with adoption, because the scale is the entire point. Gartner’s figure: at the start of 2025, under five percent of enterprise applications had task-specific AI agents. By the end of this year, forty percent. That is roughly eight-fold in twelve months. Underneath that curve the usage is higher still — seventy-eight to eighty percent of employees and teams are actively using AI in their work. But only about fourteen percent of that use is sanctioned through proper channels. And eighty-eight percent of organizations have already reported a suspected or confirmed AI security event.
Now the right-hand side — the part that is already public. A hundred and seventy-five thousand Ollama inference hosts reachable on the open internet, across a hundred and thirty countries. Over two hundred thousand exposed Ray dashboards. Almost fifteen thousand Streamlit apps, most of them unauthenticated. Eleven thousand vector databases, most with no authentication at all. Seven thousand MCP servers on public IPs. None of that took phishing or an insider. It is indexed, and it is sitting there.
Here is the part to hold onto. Every one of those deployments was a reasonable decision by a competent team. Nobody did anything wrong. But the aggregate is a sprawling shadow surface that nobody mapped.
Slide 4   Shodan exhibit
1:00 budget      running clock 3:45
[ Advance to slide 4. Confirm your Shodan screenshot is placed in the capture frame before the talk. ]
And you do not need a research budget to see this. You need a search box. This is a live Shodan query — port eleven-four-three-four, and the string “Ollama is running.” That is the whole query, and it returns a wall of inference endpoints. Three things to point out. First, no authentication — the endpoint answers anyone who connects. Second, the model list is exposed; one request tells you every model that host is running. Third, facet the results by country and you will see this is genuinely everywhere. Pillar Security documented exactly this in the wild: attackers use Shodan and Censys to find these hosts, and once an endpoint shows up in scan results, exploitation attempts begin within hours.
Slide 5   Threat convergence
2:00 budget      running clock 5:45
[ Advance to slide 5. The target and the operator above, four named campaigns below. ]
That is the target. Now the other side — who is doing the attacking. Two shifts are colliding. The target shift you just saw: hundreds of thousands of unauthenticated AI services, indexed and exploitable at scale. The operator shift is that offensive work is now AI-assisted — autonomous agents already drive roughly one in eight reported AI breaches, a figure from HiddenLayer’s 2026 threat report, and one operator with an agentic coding tool runs the whole kill chain at machine speed.
Four named operations make that concrete, and the first is the reason this tool exists. Operation Bizarre Bazaar, documented by Pillar Security in January, is the first LLMjacking campaign with a real commercial marketplace behind it — and it runs in three stages. Distributed scanners crawl the internet for exposed AI endpoints. A validation tier confirms each one by testing it with throwaway placeholder keys. And a marketplace resells the confirmed access at forty to sixty percent off retail — thirty-five thousand sessions in Pillar’s honeypot alone. What stayed with me was not that the endpoints were exposed; we already knew that. It was that someone had productized the entire chain. The other three operations confirm the pattern. GTG-1002, where AI ran eighty to ninety percent of a state-sponsored intrusion across roughly thirty organizations. The MCP supply chain — one transport flaw recurring as a CVE pattern across unrelated packages. And Mexico and Vercel — solo operators who breached nine government agencies and a major developer platform with the same authorization-pretense trick.
Put the two shifts together. Target-rich infrastructure on one side, capability-rich operators on the other — and they meet inside the enterprise. Bizarre Bazaar proved the discover-validate-exploit chain can be industrialized. So I built the version that runs it inward.
Slide 6   AI-native surfaces — MCP and RAG
1:15 budget      running clock 7:00
[ Advance to slide 6. Two columns: MCP, RAG. ]
Two of those surfaces deserve a closer look, because they have no traditional analog — nothing in your existing security model maps neatly onto them. The first is MCP, the Model Context Protocol — the integration fabric for agentic AI, the way an agent reaches tools, files, and data. Over a hundred and fifty million SDK downloads, and it arrived with the security maturity of a brand-new package ecosystem. There is a systemic weakness in its STDIO transport, and that is the recurring CVE pattern I just mentioned. A single exposed MCP server can bridge an agent straight to file systems, databases, and shell access.
The second is RAG — retrieval-augmented generation. RAG moved the trust boundary into the data layer. The vector databases behind it get deployed without authentication, and the retrieval pipeline trusts its corpus implicitly. Poison the corpus and you steer the model, with no access to the model itself. Both are dependency categories that reached production faster than anyone built tooling to secure them. Which brings me to the lab.
Slide 7   Lab topology
1:30 budget      running clock 8:30
[ Advance to slide 7. The topology diagram: operator box, subnet, four target hosts. ]
This is the lab. Five virtual machines on one isolated subnet — the 172.16.50 range. Four are targets, one is the operator box. The design choice that matters most: every service is a native install. No containers. And that is deliberate. Real shadow AI is not stood up by an infrastructure team running orchestration — it is a developer running an install script. Native installs leave the artifacts on disk that a scanner actually finds; containers would hide them. So the lab behaves like the real thing.
Four target hosts, twenty-nine AI and ML endpoints between them. ailab-dev is a developer workstation — Ollama, Jupyter, an MCP server. ailab-ml is the big one, the shared ML platform — twelve services, from ChromaDB and MLflow to Ray, LiteLLM, Kubeflow and a stack of inference servers. ailab-ds is data science — the vector databases, Weaviate and Qdrant, plus more Jupyter. ailab-app is shared AI apps. The operator box runs aipostex, and one command from there reaches the entire subnet. That command is the first demo.
Slide 8   Twelve scenarios, three tracks
1:00 budget      running clock 9:30
[ Advance to slide 8. The scenario matrix — do not read all twelve rows; frame the three tracks. ]
One slide on what the lab can actually teach, then we go to the demos. Twelve attack scenarios, in three tracks. The discovery track, scenarios one through three, is pure reconnaissance — survey what is reachable, pull a gateway’s configuration, fingerprint inference servers. The exploitation track, four through seven, is single-target — extract data from a vector database, get code execution through Jupyter, harvest credentials off the ML platform, poison a RAG pipeline. The chained track, eight through twelve, is where it gets serious — full credential chains, pipeline injection, supply-chain model tampering, MCP tool infection, and a complete multi-vector campaign the lab scores end to end. It is a curriculum. The three demos you are about to see come straight out of it.
Slide 9   Demo menu
0:45 budget      running clock 10:15
[ Advance to slide 9, then switch your display to a terminal on the operator box. ]
Three demonstrations, and I will run all three live. Demo A is the shadow AI map — one command that turns a slash-twenty-four into a typed inventory of AI infrastructure. Demo B chains a credential — a key sitting in a Jupyter notebook becomes validated access to an LLM gateway. Demo C is a credential chain across the ML platform — one harvest that crosses distributed compute, experiment tracking, pipelines, and inference. Each one ends in a proof object you could hand a defender. Let me switch to a terminal.
Slide 10   Demo A — Shadow AI map    LIVE
3:00 budget      running clock 13:15
SETUP   Terminal on the operator box, ailab-attack. Deck on the Demo A slide.
SAY   Demo A — the simplest of the three, and the most important. One command, against the whole lab subnet.
RUN   aipostex discover network --target 172.16.50.0/24
SAY   While that runs, it is probing the four hosts and fingerprinting every service it finds. This is the slowest part — give it a moment.
POINT   At the endpoint count: twenty-nine AI and ML endpoints. Not twenty-nine open ports — twenty-nine identified services, each with a family and a confidence level.
POINT   At the families line — this is the vocabulary for everything that follows. Ollama runs language models locally. Jupyter is the data-science notebook environment. ChromaDB is a vector database. MLflow tracks ML experiments. Ray is distributed compute for model training. MCP is the integration layer for AI agents. The tool identifies all six.
POINT   At the workflow targets: twenty-nine generated — concrete follow-on commands, ready to run.
POINT   At the scan mode: detection only. Exploitation is gated behind an explicit flag. By default the tool looks; it does not touch.
SAY   That is the map. The slash-twenty-four is no longer a range of addresses — it is a typed inventory of AI infrastructure.
IF IT BREAKS   If the scan stalls, stop it and walk the captured result on the slide. Do not wait on a hanging probe.
Slide 11   Demo B — Notebook secret to gateway    LIVE
3:45 budget      running clock 17:00
SETUP   Terminal on the operator box. Deck on the Demo B slide.
SAY   Demo B. This is the one that should worry you. We take a credential nobody thinks about, and turn it into real access.
RUN   aipostex jupyter --target http://172.16.50.10:8888 \
     read-notebook --path notebooks/rag-prototype.ipynb
POINT   At the result: it mined three secrets out of the prototype notebook — an OpenAI key, an Anthropic key, and a Postgres connection string. Each one tagged read-confirmed — meaning we actually pulled it out, not guessed it might be there.
SAY   On their own, three secrets in a notebook are just findings. The real question is what they unlock.
RUN   aipostex openai-compat --target http://172.16.50.20:4000 \
     --api-key sk-proj-FAKE-notebook-key-1234567890abcdef auth-sweep
POINT   At the proxy result: auth-sweep replays the OpenAI key against the LiteLLM proxy on the ML platform — and a LiteLLM proxy is a gateway that fronts many model providers behind one endpoint. The proxy accepts the key and enumerates the models behind it. And notice what auth-sweep is — it is the exact validator move from Operation Bizarre Bazaar, confirming a key is live before it is used. Same technique, pointed at our own gateway.
SAY   That notebook key just became an aggregator. One forgotten credential, and you are inside the gateway that fronts the company’s models.
Note   --api-key is the canonical flag; --token still works as an alias. The OpenAI-shaped key is the right one for an OpenAI-compatible proxy. If the mock proxy returns a 500 on inference, say “we are enumerating what is behind the gateway” — do not claim a live model call.
SAY   No credential was typed by hand. The notebook produced the key; the workflow carried it to the gateway.
IF IT BREAKS   Fall back to the captured output on the slide. The chain — notebook to key to gateway — is the point; deliver it even if a command misfires.
Slide 12   Demo C — ML platform credential chain    LIVE
4:15 budget      running clock 21:15
SETUP   Terminal on the operator box. Deck on the Demo C slide.
SAY   Demo C — same idea, wider blast radius. The ML platform is one host, but four teams share it, and they share secrets without realizing it.
RUN   aipostex ray --target http://172.16.50.20:8265 jobs --format jsonl --output findings.jsonl
POINT   Ray is the cluster framework teams use to run distributed model-training jobs — and fourteen credentials were harvested straight out of those jobs’ runtime environments. The summary gives the count; the raw values are written to the findings file.
RUN   aipostex report view findings.jsonl --credentials --commands
POINT   The operator view. Actionable pivots — the MLflow URLs the tool can act on — separated from viewer-only secrets. Leaked credentials become concrete next commands.
RUN   aipostex mlflow --target http://172.16.50.20:5000 enum
POINT   Follow the chain. Ray told us where MLflow lives — and MLflow is the experiment-tracking and model-registry server data-science teams run. It gives up the experiments, the registry, and the next layer of URLs.
RUN   aipostex kubeflow --target http://172.16.50.20:9000 pipelines
POINT   Kubeflow runs ML pipelines on Kubernetes — it is the orchestration layer above all of this. pipelines exposes the pipeline IDs and parameters, and only after that does a gated run action make sense.
SAY   Distributed compute, experiment tracking, and orchestration — one platform, credentials flowing between all of them. Every finding tagged at each step, so you can see exactly how far each one is proven.
SAY   That is the chain. It never left a single host, and it crossed four teams’ worth of services.
IF IT BREAKS   If the Ray output runs long, the findings are already saved to the file — jump straight to report view. The operator view is what matters live: what we captured, and what we can honestly run next.
Slide 13   Product proof
1:30 budget      running clock 22:45
[ Return to slides. Advance to slide 13 — the stats, the dialect point, the proof-strength ladder. ]
You have now seen aipostex work three times. Here is what it actually is. A hundred and twenty-three vulnerability templates — sixty-five for detection, fifty-eight for exploitation. Seventeen exploitation modules, one per service surface. And twenty-seven checks tied to named CVEs, GitHub advisories, and threat advisories.
Why build a new tool at all? Start with Operation Bizarre Bazaar. That campaign worked because the adversary had a pipeline — scan, validate, exploit. aipostex is that pipeline turned inward: discovery is the scanner stage, the auth-sweep you saw in Demo B is the validator stage, and the exploitation modules are the rest. The second reason is dialect. Existing scanners speak HTTP; this surface does not — it speaks JSON-RPC, gRPC, MLflow’s REST, Ray’s serialized payloads, MCP over STDIO. A generic scanner sees an open port; aipostex sees a Ray dashboard that will accept a job, or an MLflow server carrying live credentials.
And one design point that matters for a defender: every finding is graded by proof strength. Reachable means the service answered. Read-confirmed means we pulled real data out of it — you saw that tag on the notebook secrets in Demo B. Execution-confirmed means we ran code on the host. That grading lets a defender triage by certainty: chase what is proven first, not what is merely possible.
Slide 14   Defender actions
2:00 budget      running clock 24:45
[ Advance to slide 14. The four moves. ]
So what do you do with this. Four moves — and none of them needs a new vendor or a new budget line.
One: inventory before exposure. Assume there are internal AI services right now that nobody registered. Run internal-range fingerprinting on a schedule — the same attacker logic I showed you, pointed inward. The tool already does this; it is the discover command against your own ranges.
Two: authentication is not optional. The most common finding on this whole surface is a service with no auth, and the most common excuse is that it is only bound to localhost. Localhost binding is not a security control. Default-no-auth services need an auth proxy in front of them, and an unauthenticated AI service that can reach production should fail closed.
Three: treat aggregators as crown jewels. You saw it in Demo B — one compromised LLM proxy is every provider tenant behind it, at once. Vault-managed keys, scoped tokens, a rate ceiling per key, and an alert the moment one key enumerates multiple providers.
Four: route AI logs to the SOC. Inference endpoints, MCP servers, MLflow, vector databases all generate logs, and most of those logs currently go nowhere. Pipe them in, baseline normal behavior, alert on the deviation. None of this is exotic — it is the discipline you already apply everywhere else, extended to the part of the estate that grew without you.
Slide 15   Close
0:45 budget      running clock 25:30
[ Advance to slide 15 — the close. ]
One sentence to take away. Shadow AI is unmanaged infrastructure — it is discoverable, it is exploitable, and right now the people doing the mapping are not the defenders. The lab, the three demonstrations, and the tool all exist to change which side gets there first. Everything is open source, at the links on the screen. And the single fastest thing you can do after this meeting is point that discover command at one of your own internal ranges and look at what comes back. I think the result will make the case better than I just did. Thank you — I am happy to take questions.
Backup slides
Two slides sit after the close. They are not part of the run — hold them for questions.
Sourcing and claims
Use this if a number is challenged. Three things are solid: the lab topology, the named campaigns, and the slide 3 figures — Gartner for adoption; SentinelLABS, Oligo, UpGuard, and OX Security for the exposed-surface counts; HiddenLayer’s 2026 report for the one-in-eight breach figure. Two things to flag honestly. First, the lab’s planted-findings count: three internal sources disagree at 191, 185, and 169, which is why the deck never states a single number for it. Second, the aipostex counts — 123 templates, 17 modules, 27 advisory checks — come from the project’s own build records; confirm them against the current build before the talk, since the repository is not yet public.
MITRE ATLAS and OWASP mapping
Use this if someone asks you to map Operation Bizarre Bazaar to a framework. It lists seven MITRE ATLAS techniques, three entries from the OWASP LLM Top 10, and two from the OWASP Top 10 for Agentic AI. The point to make alongside it: the campaign is not exotic — it is a known set of techniques, executed at commercial scale against an unguarded surface.
Delivery notes
•     Pace. The narration is written for roughly 140 words per minute. Content runs about 25:30, leaving 4:30 in the slot for questions and slippage. If you naturally speak faster, you will finish early — that is fine; it becomes question time.
•     Demos. Budgeted at 3:00, 3:45, and 4:15. The only real risk to the clock is a hanging command. Each demo has an “if it breaks” line — use the captured output on the slide rather than waiting. Do not let one stalled probe spend the buffer.
•     Slide 4. The Shodan slide is a capture frame. Place a current screenshot of the query into it before the talk — a real result count reads as evidence, a placeholder does not.
•     Demo B caveat. If the mock proxy returns a 500 on an inference call, stay on enumeration language — you are showing what sits behind the gateway, not invoking a model.
•     The one sentence. If you forget everything else, land the thesis: shadow AI is unmanaged infrastructure. Every slide is in service of that line.
