import { useEffect, useRef, useState } from 'react';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { ArrowRight, Terminal, GitPullRequest, RotateCcw, AlertTriangle, Menu, X, MousePointer2, Check, ShieldCheck, Database, Zap, FileSearch, Gauge, Layers3 } from 'lucide-react';

gsap.registerPlugin(ScrollTrigger);

const GITHUB_URL = "https://github.com/Paracosm-Lab/taskrail";

const navItems = [
  { label: "Solutions", href: "/solutions" },
  { label: "About", href: "/#about" },
  { label: "Docs", href: "/#docs" }
];

const GitHubMark = ({ size = 20 }) => (
  <svg
    aria-hidden="true"
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="currentColor"
    className="shrink-0"
  >
    <path d="M12 2C6.48 2 2 6.58 2 12.24c0 4.52 2.87 8.35 6.84 9.7.5.1.68-.22.68-.49 0-.24-.01-.88-.01-1.73-2.78.62-3.37-1.37-3.37-1.37-.45-1.18-1.11-1.5-1.11-1.5-.91-.64.07-.63.07-.63 1 .07 1.53 1.06 1.53 1.06.9 1.57 2.35 1.12 2.92.85.09-.66.35-1.12.64-1.38-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.31.1-2.72 0 0 .84-.28 2.75 1.05A9.36 9.36 0 0 1 12 6.93c.85 0 1.7.12 2.5.34 1.9-1.33 2.74-1.05 2.74-1.05.55 1.41.2 2.46.1 2.72.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.79-4.57 5.05.36.32.68.95.68 1.92 0 1.38-.01 2.49-.01 2.83 0 .27.18.59.69.49A10.08 10.08 0 0 0 22 12.24C22 6.58 17.52 2 12 2Z" />
  </svg>
);

// --- UTILITIES & MICRO-INTERACTIONS ---

const MagneticButton = ({ children, className = "", href, onClick, variant = "primary" }) => {
  const buttonRef = useRef(null);
  
  useEffect(() => {
    const btn = buttonRef.current;
    if (!btn) return;
    
    // Simpler magnetic effect
    const handleMouseMove = (e) => {
      const { clientX, clientY } = e;
      const { height, width, left, top } = btn.getBoundingClientRect();
      const x = clientX - (left + width / 2);
      const y = clientY - (top + height / 2);
      gsap.to(btn, { x: x * 0.2, y: y * 0.2, duration: 0.5, ease: "power2.out" });
    };
    
    const handleMouseLeave = () => {
      gsap.to(btn, { x: 0, y: 0, duration: 0.7, ease: "elastic.out(1, 0.3)" });
    };
    
    btn.addEventListener("mousemove", handleMouseMove);
    btn.addEventListener("mouseleave", handleMouseLeave);
    
    return () => {
      btn.removeEventListener("mousemove", handleMouseMove);
      btn.removeEventListener("mouseleave", handleMouseLeave);
    };
  }, []);

  const baseStyle = "group relative overflow-hidden px-6 py-3 rounded-full font-sans font-bold transition-all duration-300 flex items-center justify-center gap-2 will-change-transform";
  const variants = {
    primary: "bg-accent text-white",
    secondary: "bg-dark text-white",
    ghost: "bg-transparent text-dark border border-dark/20 hover:border-dark"
  };
  
  const hoverColor = variant === "primary" ? "bg-dark" : variant === "secondary" ? "bg-accent" : "bg-dark";

  const Component = href ? "a" : "button";

  return (
    <Component
      ref={buttonRef}
      href={href}
      onClick={onClick}
      className={`${baseStyle} ${variants[variant]} ${className} hover:scale-[1.03] active:scale-[0.98]`}
      style={{ transitionTimingFunction: "cubic-bezier(0.25, 0.46, 0.45, 0.94)" }}
    >
      <span className="relative z-10 flex items-center gap-2">{children}</span>
      <span className={`absolute inset-0 z-0 ${hoverColor} transform translate-y-[101%] transition-transform duration-500 ease-[cubic-bezier(0.19,1,0.22,1)] group-hover:translate-y-0 rounded-full`}></span>
    </Component>
  );
};

// --- COMPONENTS ---

const Navbar = () => {
  const navRef = useRef(null);
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const ctx = gsap.context(() => {
      ScrollTrigger.create({
        start: "top -100",
        end: 99999,
        toggleClass: { className: "nav-scrolled", targets: navRef.current },
        onUpdate: (self) => {
          if (self.progress > 0) {
            gsap.to(navRef.current, {
              backgroundColor: "rgba(245, 243, 238, 0.8)",
              backdropFilter: "blur(16px)",
              borderColor: "rgba(17, 17, 17, 0.1)",
              color: "#111111",
              duration: 0.3
            });
          } else {
            gsap.to(navRef.current, {
              backgroundColor: "transparent",
              backdropFilter: "blur(0px)",
              borderColor: "transparent",
              color: "#E8E4DD",
              duration: 0.3
            });
          }
        }
      });
    });
    return () => ctx.revert();
  }, []);

  return (
    <nav ref={navRef} className="fixed top-4 left-1/2 -translate-x-1/2 w-[95%] max-w-7xl z-50 rounded-full border border-transparent text-primary transition-all duration-300">
      <div className="px-6 py-4 flex items-center justify-between">
        <div className="font-sans font-bold text-4xl tracking-tighter flex items-center gap-4 cursor-pointer hover:-translate-y-[1px] transition-transform">
          <div className="w-7 h-7 bg-accent rounded-md"></div>
          TASKRAIL
        </div>
        
        <div className="hidden md:flex items-center gap-10 font-sans font-bold text-xl tracking-tight">
          {navItems.map((item) => (
            <a key={item.label} href={item.href} className="hover:-translate-y-[1px] transition-transform hover:text-accent">
              {item.label}
            </a>
          ))}
        </div>
        
        <div className="hidden md:block">
          <MagneticButton href={GITHUB_URL} variant="primary" className="py-3 px-6 text-base">
            <GitHubMark size={18} /> View on GitHub
          </MagneticButton>
        </div>
        
        <button className="md:hidden" onClick={() => setIsOpen(!isOpen)}>
          {isOpen ? <X /> : <Menu />}
        </button>
      </div>
      
      {/* Mobile Menu */}
      {isOpen && (
        <div className="absolute top-full left-0 w-full mt-2 bg-background/95 backdrop-blur-xl border border-dark/10 rounded-[2rem] p-6 flex flex-col gap-4 shadow-2xl text-dark md:hidden">
          {navItems.map((item) => (
            <a key={item.label} href={item.href} onClick={() => setIsOpen(false)} className="text-xl font-sans font-bold border-b border-dark/5 pb-2">
              {item.label}
            </a>
          ))}
          <MagneticButton href={GITHUB_URL} variant="primary" className="mt-4 w-full justify-center">
            <GitHubMark size={18} /> View on GitHub
          </MagneticButton>
        </div>
      )}
    </nav>
  );
};

const Hero = () => {
  const containerRef = useRef(null);

  useEffect(() => {
    const ctx = gsap.context(() => {
      gsap.from(".hero-elem", {
        y: 60,
        opacity: 0,
        duration: 1.2,
        stagger: 0.1,
        ease: "power3.out",
        delay: 0.2
      });
    }, containerRef);
    return () => ctx.revert();
  }, []);

  return (
    <section ref={containerRef} className="relative h-[100dvh] w-full overflow-hidden bg-dark">
      {/* Background Image with Gradient Overlay */}
      <div className="absolute inset-0 w-full h-full">
        <img 
          src="https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?q=80&w=2940&auto=format&fit=crop" 
          alt="Brutalist Architecture" 
          className="w-full h-full object-cover opacity-60"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-dark via-dark/80 to-transparent"></div>
        <div className="absolute inset-0 bg-dark/30 mix-blend-multiply"></div>
      </div>

      {/* Content */}
      <div className="relative h-full w-full max-w-7xl mx-auto px-6 flex flex-col justify-center pt-24 pb-8 md:pt-28 md:pb-10 lg:pt-32 lg:pb-12">
        <div className="max-w-4xl">
          <div className="mb-6 flex items-center gap-3 hero-elem">
            <span className="px-3 py-1 bg-accent/20 text-accent rounded-full font-mono text-xs font-bold uppercase tracking-widest border border-accent/30 backdrop-blur-sm">
              Agent operations control plane
            </span>
          </div>
          
          <h1 className="text-primary flex flex-col gap-0 leading-[0.85] mb-6">
            <span className="hero-elem font-sans font-bold text-5xl md:text-7xl lg:text-[5rem] tracking-tight text-balance">
              Control the
            </span>
            <span className="hero-elem font-serif italic text-7xl md:text-8xl lg:text-[7.5rem] text-accent pr-4 drop-shadow-2xl">
              execution.
            </span>
          </h1>
          
          <p className="hero-elem text-primary/80 font-sans text-lg md:text-2xl max-w-2xl mb-7 leading-snug text-balance border-l-2 border-accent pl-6 py-1">
            Taskrail gives CTOs and platform teams staged execution, cost visibility, observability, and human gates for AI-assisted engineering work.
          </p>
          
          <div className="hero-elem flex flex-wrap gap-4">
            <MagneticButton href={GITHUB_URL} variant="primary" className="py-4 px-8 text-lg">
              <GitHubMark size={20} /> View on GitHub
            </MagneticButton>
            <MagneticButton href="#docs" variant="ghost" className="py-4 px-8 text-lg text-primary border-primary/30 hover:border-primary hover:text-dark">
              Read Docs <ArrowRight size={20} />
            </MagneticButton>
          </div>
        </div>
      </div>
    </section>
  );
};

// Features Interactive Cards
const DiagnosticShuffler = () => {
  const [cards, setCards] = useState([
    { id: 1, label: "HUMAN_REVIEW", status: "BLOCKED", color: "text-blue-500", bg: "bg-blue-500/10" },
    { id: 2, label: "RUN_CHECKS", status: "RUNNING", color: "text-accent", bg: "bg-accent/10" },
    { id: 3, label: "DRAFT_PATCH", status: "READY", color: "text-dark/50", bg: "bg-dark/5" }
  ]);

  useEffect(() => {
    const interval = setInterval(() => {
      setCards(prev => {
        const newCards = [...prev];
        const last = newCards.pop();
        newCards.unshift(last);
        return newCards;
      });
    }, 3000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="bg-white rounded-[2rem] p-8 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-dark/5 h-full flex flex-col hover:-translate-y-2 transition-transform duration-500">
      <div className="mb-8">
        <GitPullRequest className="text-accent mb-4" size={32} />
        <h3 className="font-sans font-bold text-2xl mb-2">Definition of Done</h3>
        <p className="text-dark/70 font-sans">Stages define inputs, predicates, ownership, and checks before work can advance.</p>
      </div>
      
      <div className="relative flex-grow min-h-[200px] flex items-center justify-center">
        {cards.map((card, i) => {
          const isTop = i === 0;
          return (
            <div 
              key={card.id}
              className={`absolute w-full max-w-[280px] p-4 rounded-2xl border transition-all duration-700 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${isTop ? 'bg-white border-dark/10 shadow-lg z-30 scale-100 opacity-100 translate-y-0' : i === 1 ? 'bg-background border-dark/5 z-20 scale-95 opacity-80 -translate-y-4' : 'bg-background border-dark/5 z-10 scale-90 opacity-40 -translate-y-8'}`}
            >
              <div className="flex justify-between items-center mb-2">
                <span className="font-mono text-xs font-bold">{card.label}</span>
                <span className={`text-[10px] px-2 py-1 rounded-full font-mono font-bold ${card.color} ${card.bg}`}>
                  {card.status}
                </span>
              </div>
              <div className="h-1.5 w-full bg-dark/5 rounded-full overflow-hidden">
                <div className={`h-full w-2/3 ${isTop ? 'bg-accent' : 'bg-dark/20'} rounded-full`}></div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

const TelemetryTypewriter = () => {
  const [text, setText] = useState("");
  const fullText = "> adapter=codex connected\n> stage=security_scan running\n> cost=$0.18 retry=1\n> artifact=severity_report saved\n> predicate=human_review_required";
  
  useEffect(() => {
    let current = 0;
    const interval = setInterval(() => {
      setText(fullText.slice(0, current));
      current++;
      if (current > fullText.length) {
        current = 0;
        setTimeout(() => {}, 2000); // Pause before restart
      }
    }, 50);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="bg-dark text-primary rounded-[2rem] p-8 shadow-[0_8px_30px_rgb(0,0,0,0.1)] border border-dark h-full flex flex-col hover:-translate-y-2 transition-transform duration-500">
      <div className="mb-8">
        <Terminal className="text-primary mb-4" size={32} />
        <h3 className="font-sans font-bold text-2xl mb-2 text-white">Observable Execution</h3>
        <p className="text-primary/70 font-sans">Run agents, CI, and shell with artifacts, traces, cost, and status in one lifecycle.</p>
      </div>
      
      <div className="flex-grow bg-[#0A0A0A] rounded-xl p-4 font-mono text-sm overflow-hidden relative border border-primary/10">
        <div className="absolute top-0 w-full left-0 bg-primary/5 px-4 py-2 border-b border-primary/10 flex items-center justify-between">
          <span className="text-xs text-primary/50">runtime.log</span>
          <span className="flex items-center gap-2 text-[10px] text-accent"><span className="w-1.5 h-1.5 rounded-full bg-accent animate-pulse"></span>LIVE FEED</span>
        </div>
        <div className="mt-10 whitespace-pre-wrap text-primary/80">
          {text}<span className="inline-block w-2 h-4 bg-accent ml-1 animate-pulse align-middle"></span>
        </div>
      </div>
    </div>
  );
};

const CursorProtocolScheduler = () => {
  const containerRef = useRef(null);
  const cursorRef = useRef(null);
  const dayRef = useRef(null);
  
  useEffect(() => {
    const ctx = gsap.context(() => {
      const tl = gsap.timeline({ repeat: -1, repeatDelay: 1 });
      
      tl.set(cursorRef.current, { x: 0, y: 0, scale: 1, opacity: 0 })
        .to(cursorRef.current, { opacity: 1, duration: 0.3 })
        .to(cursorRef.current, { x: 120, y: 60, duration: 1, ease: "power2.inOut" })
        .to(cursorRef.current, { scale: 0.8, duration: 0.1 })
        .to(dayRef.current, { backgroundColor: "#E63B2E", color: "white", duration: 0.1 })
        .to(cursorRef.current, { scale: 1, duration: 0.1 })
        .to(cursorRef.current, { x: 220, y: 150, duration: 0.8, ease: "power2.inOut" })
        .to(cursorRef.current, { scale: 0.8, duration: 0.1 })
        .to(cursorRef.current, { opacity: 0, duration: 0.2 })
        .to(dayRef.current, { backgroundColor: "rgba(17,17,17,0.05)", color: "#111111", duration: 0.5, delay: 0.5 });
    }, containerRef);
    return () => ctx.revert();
  }, []);

  return (
    <div className="bg-white rounded-[2rem] p-8 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-dark/5 h-full flex flex-col hover:-translate-y-2 transition-transform duration-500" ref={containerRef}>
      <div className="mb-8">
        <RotateCcw className="text-accent mb-4" size={32} />
        <h3 className="font-sans font-bold text-2xl mb-2">Recovery Paths</h3>
        <p className="text-dark/70 font-sans">Failed or risky work retries, blocks, or escalates through visible operator paths.</p>
      </div>
      
      <div className="flex-grow relative flex flex-col items-center justify-center p-4">
        {/* SVG Cursor */}
        <div ref={cursorRef} className="absolute z-20 pointer-events-none drop-shadow-xl" style={{ top: '20px', left: '20px' }}>
          <MousePointer2 className="text-dark fill-dark" size={24} />
        </div>
        
        <div className="grid grid-cols-7 gap-2 w-full max-w-[240px] mb-6">
          {['S','M','T','W','T','F','S'].map((d, i) => (
            <div key={i} className="text-center font-mono text-[10px] text-dark/40 font-bold">{d}</div>
          ))}
          {Array.from({length: 14}).map((_, i) => (
            <div 
              key={i} 
              ref={i === 10 ? dayRef : null}
              className="aspect-square rounded-md bg-dark/5 flex items-center justify-center font-mono text-xs transition-colors duration-300"
            >
              {i + 1}
            </div>
          ))}
        </div>
        
        <div className="bg-dark text-white text-xs font-mono px-4 py-2 rounded-full flex items-center gap-2 mt-auto self-end">
          <AlertTriangle size={12} className="text-accent" /> ESCALATE
        </div>
      </div>
    </div>
  );
};

const Features = () => {
  return (
    <section id="features" className="py-24 md:py-32 px-6 relative">
      <div className="max-w-7xl mx-auto">
        <div className="mb-16 md:mb-24">
          <h2 className="font-sans font-bold text-4xl md:text-5xl max-w-2xl text-balance">
            Control primitives for agentic engineering work.
          </h2>
        </div>
        
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <DiagnosticShuffler />
          <TelemetryTypewriter />
          <CursorProtocolScheduler />
        </div>
      </div>
    </section>
  );
};

const solutions = [
  {
    category: "DevOps",
    slug: "migration-safety",
    title: "Migration Safety",
    text: "Map impact, enumerate risk, draft rollback, test recovery, then stop for human review.",
    icon: Database,
    stages: "scan -> risk -> rollback -> review",
    pain: "Unsafe migrations hide risk until deploy time. Teams need impact mapping, rollback plans, staging validation, and human review before cutover.",
    artifacts: ["Impact map", "Risk assessment", "Rollback plan", "Rollback test results", "Migration runbook"]
  },
  {
    category: "Development",
    slug: "dependency-upgrades",
    title: "Dependency Upgrades",
    text: "Audit stale packages, prioritize safe groups, draft one upgrade, run checks, and package review.",
    icon: Layers3,
    stages: "audit -> prioritize -> patch -> test",
    pain: "Dependency work piles up because each upgrade mixes security risk, compatibility risk, changelog review, tests, and merge judgment.",
    artifacts: ["Dependency audit", "Upgrade plan", "Upgrade patch", "Test results", "Review package"]
  },
  {
    category: "Development",
    slug: "feature-development",
    title: "Feature Development",
    text: "Decompose product work, build patches, run checks, and package reviewable implementation output.",
    icon: GitPullRequest,
    stages: "intake -> build -> test -> review",
    pain: "Agent-written feature work needs decomposition, focused implementation, tests, review context, and a clear definition of done.",
    artifacts: ["Intake brief", "Task breakdown", "Implementation patch", "Test results", "Review notes"]
  },
  {
    category: "Development",
    slug: "dead-code-removal",
    title: "Dead Code Removal",
    text: "Find unused code, verify references, draft removals, and require review before deleting anything.",
    icon: RotateCcw,
    stages: "scan -> verify -> remove -> review",
    pain: "Dead code is risky to remove because false positives can break hidden paths, feature flags, or operational scripts.",
    artifacts: ["Candidate list", "Reference scan", "Removal patch", "Verification report"]
  },
  {
    category: "Development",
    slug: "api-docs-sync",
    title: "API Docs Sync",
    text: "Scan endpoints, diff stale docs, draft updates, validate examples, and hold changes for review.",
    icon: FileSearch,
    stages: "scan -> diff -> docs -> validate",
    pain: "API docs drift because endpoint changes, serializer behavior, examples, and docs updates live in separate workflows.",
    artifacts: ["Endpoint inventory", "Documentation diff", "Drafted docs", "Validation results"]
  },
  {
    category: "DevOps",
    slug: "security-scan",
    title: "Security Scan",
    text: "Classify exploitability, draft fixes, validate patches, and require security-aware review.",
    icon: ShieldCheck,
    stages: "scan -> classify -> fix -> review",
    pain: "Security scanners create findings, but teams still need severity classification, patch drafting, validation, and human review.",
    artifacts: ["Vulnerability scan", "Severity classification", "Fix patches", "Test results"]
  },
  {
    category: "DevOps",
    slug: "credential-rotation",
    title: "Credential Rotation",
    text: "Map secrets and dependencies, score rotation risk, and draft human-executed rotation plans.",
    icon: ShieldCheck,
    stages: "scan -> map -> risk -> plan",
    pain: "Credential rotation is risky when dependencies, restart needs, health checks, and rollback paths are unclear.",
    artifacts: ["Credential inventory", "Dependency map", "Risk assessment", "Rotation plan"]
  },
  {
    category: "Testing",
    slug: "error-handling-audit",
    title: "Error Handling Audit",
    text: "Find unsafe rescue paths, classify operational risk, draft fixes, and validate before review.",
    icon: AlertTriangle,
    stages: "scan -> classify -> fix -> test",
    pain: "Unsafe error handling hides real failures, swallows context, and turns recoverable problems into incidents.",
    artifacts: ["Error pattern scan", "Severity report", "Fix patches", "Validation results"]
  },
  {
    category: "Testing",
    slug: "data-integrity",
    title: "Data Integrity",
    text: "Define validation rules, scan records, assess damage, and draft repair plans with review gates.",
    icon: Database,
    stages: "rules -> scan -> assess -> repair",
    pain: "Data issues need explicit rules, blast-radius assessment, repair planning, and review before any fix runs.",
    artifacts: ["Integrity rules", "Violation scan", "Damage assessment", "Repair plan"]
  },
  {
    category: "Testing",
    slug: "query-health",
    title: "Query Health",
    text: "Collect slow queries, analyze risk, draft fixes, and validate performance-sensitive changes.",
    icon: Gauge,
    stages: "collect -> analyze -> fix -> test",
    pain: "Slow query work needs evidence, risk analysis, careful patching, and validation before changing production paths.",
    artifacts: ["Query inventory", "Performance analysis", "Fix patches", "Validation results"]
  },
  {
    category: "DevOps",
    slug: "incident-readiness",
    title: "Incident Readiness",
    text: "Score services before they break: alerts, runbooks, dashboards, ownership, and recovery gaps.",
    icon: Gauge,
    stages: "inventory -> score -> gaps -> improve",
    pain: "Most readiness gaps are discovered during incidents: missing runbooks, weak alerts, unclear ownership, and poor dashboards.",
    artifacts: ["Service inventory", "Readiness scores", "Gap analysis", "Improvement drafts"]
  },
  {
    category: "DevOps",
    slug: "background-jobs",
    title: "Background Jobs",
    text: "Audit workers for retries, timeouts, idempotency, error capture, logging, and metrics.",
    icon: Terminal,
    stages: "inventory -> score -> patch -> test",
    pain: "Async jobs fail silently when retry policy, timeouts, idempotency, logging, and metrics are inconsistent.",
    artifacts: ["Job inventory", "Observability scorecard", "Job patches", "Test results"]
  },
  {
    category: "DevOps",
    slug: "failure-readiness",
    title: "Failure Readiness",
    text: "Ingest incident signals, cluster failures, assess alert quality, and draft runbooks.",
    icon: AlertTriangle,
    stages: "signals -> cluster -> runbook -> validate",
    pain: "Teams need to know whether alerts and runbooks are usable before a real production incident.",
    artifacts: ["Operational signals", "Failure clusters", "Instrumentation assessment", "Draft runbooks"]
  },
  {
    category: "DevOps",
    slug: "infrastructure-drift",
    title: "Infrastructure Drift",
    text: "Compare expected and actual infrastructure, classify drift, and draft safe sync plans.",
    icon: Layers3,
    stages: "collect -> diff -> classify -> plan",
    pain: "Infrastructure drift accumulates quietly until deploys, incidents, or security reviews expose the mismatch.",
    artifacts: ["Config inventory", "Drift diff", "Drift classification", "Sync plan"]
  },
  {
    category: "DevOps",
    slug: "logging-audit",
    title: "Logging Audit",
    text: "Find inconsistent logs, assess quality, draft standards, and patch weak instrumentation.",
    icon: Terminal,
    stages: "scan -> assess -> standard -> fix",
    pain: "Inconsistent logs make incidents harder to diagnose and increase the cost of every operational investigation.",
    artifacts: ["Log inventory", "Quality assessment", "Logging standard", "Fix patches"]
  },
  {
    category: "DevOps",
    slug: "post-incident-replay",
    title: "Post-Incident Replay",
    text: "Ingest artifacts, reconstruct timelines, analyze root cause, and draft follow-up updates.",
    icon: FileSearch,
    stages: "ingest -> timeline -> cause -> update",
    pain: "Post-incident work loses value when timelines, root cause, response quality, and follow-up work are scattered.",
    artifacts: ["Incident artifacts", "Timeline", "Root cause analysis", "Response evaluation", "Follow-up updates"]
  },
  {
    category: "DevOps",
    slug: "chaos-response",
    title: "Chaos Response",
    text: "Run blind staging drills that prove whether alerts, runbooks, and recovery paths actually work.",
    icon: Zap,
    stages: "disrupt -> detect -> recover -> report",
    pain: "Chaos drills often become scripted theater unless responders diagnose from alerts and runbooks without the answer key.",
    artifacts: ["Disruption plan", "Detected alerts", "Diagnosis", "Runbook execution", "Recovery report"]
  },
  {
    category: "Testing",
    slug: "test-backfill",
    title: "Test Backfill",
    text: "Find coverage gaps, generate repo-consistent tests, run them, and gate acceptance on review.",
    icon: FileSearch,
    stages: "coverage -> gaps -> tests -> review",
    pain: "Coverage gaps persist because finding the right tests, generating them, and validating them is easy to postpone.",
    artifacts: ["Coverage scan", "Prioritized gaps", "Generated tests", "Test results"]
  },
  {
    category: "Testing",
    slug: "integration-tests",
    title: "Integration Tests",
    text: "Map product flows, identify boundaries, generate integration specs, run them, and review.",
    icon: GitPullRequest,
    stages: "flows -> bounds -> tests -> run",
    pain: "Integration tests require flow mapping, boundary decisions, realistic fixtures, generated specs, and review.",
    artifacts: ["User flows", "Boundary map", "Integration specs", "Test results"]
  },
  {
    category: "Testing",
    slug: "pr-review",
    title: "PR Review",
    text: "Run architectural, coverage, and security review steps before routing work to humans.",
    icon: GitPullRequest,
    stages: "review -> coverage -> security -> verdict",
    pain: "PR review needs consistent architectural, test coverage, and security checks before humans spend attention.",
    artifacts: ["Architecture review", "Coverage check", "Security scan", "Review verdict"]
  }
];

const solutionModes = [
  {
    name: "Development",
    description: "Agent-assisted codebase maintenance where patches need reviewable artifacts and a clear completion path.",
    cookbooks: ["Feature Development", "Dependency Upgrades", "Dead Code Removal", "API Docs Sync"]
  },
  {
    name: "Testing",
    description: "Repeatable quality workflows that generate, run, verify, and package tests before human acceptance.",
    cookbooks: ["Test Backfill", "Integration Tests", "PR Review", "Error Handling Audit"]
  },
  {
    name: "DevOps",
    description: "Production-adjacent workflows where risk, recovery, cost, and operator visibility matter most.",
    cookbooks: ["Migration Safety", "Security Scan", "Incident Readiness", "Chaos Response"]
  }
];

const Solutions = () => {
  return (
    <section id="solutions" className="py-24 md:py-32 px-6 bg-dark text-primary relative overflow-hidden">
      <div className="absolute inset-0 bg-[linear-gradient(rgba(232,228,221,0.06)_1px,transparent_1px),linear-gradient(90deg,rgba(232,228,221,0.06)_1px,transparent_1px)] [background-size:48px_48px]"></div>
      <div className="max-w-7xl mx-auto relative z-10">
        <div className="mb-14 md:mb-20 max-w-4xl">
          <p className="font-mono text-accent text-sm font-bold uppercase tracking-widest mb-4">Three ways to run Taskrail</p>
          <h2 className="font-sans font-bold text-4xl md:text-6xl tracking-tight text-balance mb-6">
            One control layer for development, testing, and DevOps.
          </h2>
          <p className="font-sans text-xl text-primary/65 max-w-3xl leading-relaxed">
            Taskrail turns recurring engineering operations into reusable workflows that can run across repos, services, teams, and organizations.
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          {solutionModes.map(({ name, description, cookbooks }) => (
            <div key={name} className="space-y-4">
              <div className="rounded-[2rem] border border-accent/25 bg-accent/[0.05] p-6 min-h-[300px] flex flex-col">
                <h3 className="font-sans font-bold text-3xl mb-3">{name}</h3>
                <p className="text-primary/62 leading-relaxed mb-6">{description}</p>
                <div className="mt-auto flex flex-wrap gap-2">
                  {cookbooks.map((cookbook) => (
                    <span key={cookbook} className="rounded-full border border-primary/10 bg-primary/[0.04] px-3 py-1 font-mono text-[10px] uppercase tracking-widest text-primary/55">
                      {cookbook}
                    </span>
                  ))}
                </div>
              </div>

              <div className="space-y-4">
                {cookbooks
                  .map((cookbook) => solutions.find((solution) => solution.category === name && solution.title === cookbook))
                  .filter(Boolean)
                  .map(({ slug, title, text, icon: Icon, stages }) => (
                    <a
                      key={title}
                      href={`/cookbooks/${slug}`}
                      className="group flex min-h-[250px] flex-col rounded-[2rem] border border-primary/10 bg-primary/[0.03] p-6 transition-all duration-300 hover:-translate-y-1 hover:border-accent/50 hover:bg-primary/[0.06]"
                    >
                      <div className="flex items-center justify-between gap-4 mb-8">
                        <Icon className="text-accent shrink-0" size={28} />
                        <span className="block text-right font-mono text-[10px] uppercase tracking-widest text-primary/40 group-hover:text-accent transition-colors">
                          {stages}
                        </span>
                      </div>
                      <h3 className="font-sans font-bold text-2xl mb-3">{title}</h3>
                      <p className="text-primary/62 leading-relaxed">{text}</p>
                    </a>
                  ))}
              </div>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-col sm:flex-row items-start sm:items-center gap-4">
          <MagneticButton href="/solutions" variant="primary" className="py-4 px-8 text-lg">
            Explore all cookbooks <ArrowRight size={20} />
          </MagneticButton>
          <p className="font-mono text-xs uppercase tracking-widest text-primary/40">
            Full taxonomy: Development / Testing / DevOps
          </p>
        </div>
      </div>
    </section>
  );
};

const Philosophy = () => {
  const sectionRef = useRef(null);

  useEffect(() => {
    const ctx = gsap.context(() => {
      gsap.from(".phil-text-1", {
        scrollTrigger: {
          trigger: sectionRef.current,
          start: "top 70%",
        },
        y: 30,
        opacity: 0,
        duration: 1,
        ease: "power3.out"
      });
      
      gsap.from(".phil-text-2", {
        scrollTrigger: {
          trigger: sectionRef.current,
          start: "top 60%",
        },
        y: 40,
        opacity: 0,
        duration: 1.2,
        delay: 0.2,
        ease: "power3.out"
      });
    }, sectionRef);
    return () => ctx.revert();
  }, []);

  return (
    <section ref={sectionRef} id="philosophy" className="relative py-32 md:py-48 px-6 bg-dark text-primary overflow-hidden">
      {/* Background Parallax Texture */}
      <div 
        className="absolute inset-0 opacity-20 bg-cover bg-center"
        style={{ backgroundImage: "url('https://images.unsplash.com/photo-1518002171953-a080ee817e1f?q=80&w=2940&auto=format&fit=crop')", filter: "grayscale(100%)" }}
        data-speed="0.8"
      ></div>
      <div className="absolute inset-0 bg-dark/60"></div>
      
      <div className="relative max-w-5xl mx-auto z-10 flex flex-col gap-12 md:gap-20">
        <p className="phil-text-1 font-sans text-xl md:text-3xl text-primary/60 font-medium max-w-2xl leading-relaxed">
          Most engineering automation focuses on: <span className="text-primary">scripts, disconnected pipelines, and fragile manual handoffs.</span>
        </p>
        
        <p className="phil-text-2 font-serif italic text-4xl md:text-6xl lg:text-7xl leading-[1.1] max-w-4xl text-balance">
          We focus on: <span className="text-accent underline decoration-accent/40 underline-offset-8">explicit workflow control</span> for agentic engineering operations.
        </p>
      </div>
    </section>
  );
};

const ProtocolStep = ({ num, title, desc, animType, zIndex }) => {
  const cardRef = useRef(null);
  
  useEffect(() => {
    const ctx = gsap.context(() => {
      ScrollTrigger.create({
        trigger: cardRef.current,
        start: "top top",
        end: "+=100%",
        pin: true,
        pinSpacing: false,
        animation: gsap.to(cardRef.current, {
          scale: 0.9,
          opacity: 0.5,
          filter: "blur(10px)",
          ease: "none"
        }),
        scrub: true
      });
    }, cardRef);
    return () => ctx.revert();
  }, []);

  return (
    <div ref={cardRef} className="h-screen w-full flex items-center justify-center p-6 sticky top-0 bg-background" style={{ zIndex }}>
      <div className="w-full max-w-5xl bg-white border border-dark/10 rounded-[3rem] h-[80vh] p-10 md:p-16 flex flex-col md:flex-row items-center gap-12 shadow-2xl relative overflow-hidden">
        
        {/* Content Side */}
        <div className="flex-1 z-10">
          <div className="font-mono text-accent text-lg font-bold mb-6 border border-accent/20 px-4 py-1 rounded-full inline-block bg-accent/5">
            0{num}
          </div>
          <h2 className="font-sans font-bold text-4xl md:text-6xl mb-6 tracking-tight text-balance">{title}</h2>
          <p className="text-xl text-dark/70 font-sans max-w-lg leading-relaxed">{desc}</p>
        </div>
        
        {/* Animation Side */}
        <div className="flex-1 h-full w-full bg-background rounded-[2rem] border border-dark/5 flex items-center justify-center relative overflow-hidden">
          {/* Decorative Grid */}
          <div className="absolute inset-0 bg-[radial-gradient(#111111_1px,transparent_1px)] [background-size:20px_20px] opacity-[0.03]"></div>
          
          {animType === 1 && (
            <div className="relative w-48 h-48 border-4 border-dark/10 rounded-full flex items-center justify-center animate-[spin_10s_linear_infinite]">
              <div className="w-32 h-32 border-4 border-accent border-dashed rounded-full animate-[spin_6s_linear_infinite_reverse]"></div>
              <div className="absolute w-16 h-16 bg-dark rounded-sm animate-pulse"></div>
            </div>
          )}
          
          {animType === 2 && (
            <div className="w-full max-w-xs h-64 border border-dark/20 rounded-xl relative overflow-hidden bg-white">
              <div className="absolute inset-0 flex flex-col justify-between p-4 opacity-20">
                {Array.from({length: 6}).map((_,i) => <div key={i} className="h-4 bg-dark rounded-sm w-full"></div>)}
              </div>
              <div className="absolute top-0 left-0 w-full h-1 bg-accent shadow-[0_0_15px_rgba(230,59,46,0.8)] animate-[ping_2s_cubic-bezier(0,0,0.2,1)_infinite_alternate]"></div>
            </div>
          )}
          
          {animType === 3 && (
            <svg className="w-full h-48" viewBox="0 0 400 100">
              <path 
                d="M 0 50 L 100 50 L 120 20 L 140 80 L 160 50 L 400 50" 
                fill="none" 
                stroke="#111111" 
                strokeWidth="4" 
                strokeOpacity="0.1"
              />
              <path 
                d="M 0 50 L 100 50 L 120 20 L 140 80 L 160 50 L 400 50" 
                fill="none" 
                stroke="#E63B2E" 
                strokeWidth="4" 
                className="animate-[dash_3s_linear_infinite]"
                strokeDasharray="400"
                strokeDashoffset="400"
              />
              <style>{`@keyframes dash { to { stroke-dashoffset: 0; } }`}</style>
            </svg>
          )}
        </div>
      </div>
    </div>
  );
};

const Protocol = () => {
  return (
    <section id="protocol" className="relative bg-background">
      <div className="py-24 text-center px-6">
        <h2 className="font-serif italic text-5xl md:text-7xl">The Protocol</h2>
        <p className="mt-6 font-sans text-xl text-dark/60">How Taskrail turns agent output into controlled operational work.</p>
      </div>
      
      <div className="relative">
        <ProtocolStep 
          num="1" 
          title="Define the work." 
          desc="Set stages, inputs, predicates, ownership, and the definition of done before agents or scripts run." 
          animType={1} 
          zIndex={10} 
        />
        <ProtocolStep 
          num="2" 
          title="Execute with control." 
          desc="Run shell, CI, and AI agents through adapters while Taskrail tracks artifacts, traces, cost, and status." 
          animType={2} 
          zIndex={20} 
        />
        <ProtocolStep 
          num="3" 
          title="Verify, recover, escalate." 
          desc="Predicates decide advancement. Failed or risky work retries, blocks, or escalates to human review." 
          animType={3} 
          zIndex={30} 
        />
      </div>
    </section>
  );
};

const Conversion = () => {
  return (
    <section id="about" className="py-32 px-6 bg-white relative z-40 border-t border-dark/5">
      <div className="max-w-4xl mx-auto text-center">
        <p className="font-mono text-accent text-sm font-bold uppercase tracking-widest mb-4">About Paracosm Lab</p>
        <h2 className="font-sans font-bold text-5xl md:text-7xl mb-8 tracking-tight">Agents need an operating layer.</h2>
        <p className="font-sans text-xl text-dark/70 mb-12 max-w-2xl mx-auto">
          Every engineering team experimenting with AI agents will need an operational control plane before letting those agents touch production-adjacent work.
        </p>
        
        <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
          <MagneticButton href={GITHUB_URL} variant="primary" className="py-5 px-10 text-xl w-full sm:w-auto">
            <GitHubMark size={22} /> View on GitHub
          </MagneticButton>
          <MagneticButton href="#docs" variant="ghost" className="py-5 px-10 text-xl w-full sm:w-auto">
            View Docs
          </MagneticButton>
        </div>
        
        <div className="mt-12 grid grid-cols-1 sm:grid-cols-3 gap-4 text-sm font-mono text-dark/55">
          <span className="flex items-center justify-center gap-2"><Check size={16} className="text-accent" /> Cost per run</span>
          <span className="flex items-center justify-center gap-2"><Check size={16} className="text-accent" /> Traces and artifacts</span>
          <span className="flex items-center justify-center gap-2"><Check size={16} className="text-accent" /> Definition of done</span>
        </div>
      </div>
    </section>
  );
};

const Footer = () => {
  return (
    <footer id="docs" className="bg-dark text-primary rounded-t-[4rem] relative z-50 px-6 pt-24 pb-12 overflow-hidden mt-[-2rem]">
      <div className="max-w-7xl mx-auto grid grid-cols-1 md:grid-cols-4 gap-12 md:gap-8 relative z-10">
        
        <div className="md:col-span-2">
          <div className="font-sans font-bold text-3xl tracking-tighter flex items-center gap-3 mb-6">
            <div className="w-6 h-6 bg-accent rounded-sm"></div>
            TASKRAIL
          </div>
          <p className="font-sans text-primary/60 max-w-sm text-balance">
            Operational control plane for AI-assisted engineering work. Engineered by Paracosm Lab.
          </p>
          
          <div className="mt-12 inline-flex items-center gap-3 bg-white/5 border border-white/10 rounded-full px-4 py-2 font-mono text-xs">
            <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></div>
            SYSTEM OPERATIONAL
          </div>
        </div>
        
        <div>
          <h4 className="font-mono font-bold text-xs tracking-widest text-primary/40 uppercase mb-6">Product</h4>
          <ul className="space-y-4 font-sans">
            <li><a href="/solutions" className="hover:text-accent transition-colors">Solutions</a></li>
            <li><a href="/#docs" className="hover:text-accent transition-colors">Documentation</a></li>
            <li><a href={GITHUB_URL} className="hover:text-accent transition-colors">GitHub</a></li>
          </ul>
        </div>
        
        <div>
          <h4 className="font-mono font-bold text-xs tracking-widest text-primary/40 uppercase mb-6">Company</h4>
          <ul className="space-y-4 font-sans">
            <li><a href="/#about" className="hover:text-accent transition-colors">About Paracosm Lab</a></li>
            <li><a href="/solutions" className="hover:text-accent transition-colors">Cookbooks</a></li>
            <li><a href="mailto:greg@paracosmlab.com" className="hover:text-accent transition-colors">Contact</a></li>
          </ul>
        </div>
      </div>
      
      <div className="max-w-7xl mx-auto mt-24 pt-8 border-t border-primary/10 flex flex-col md:flex-row justify-between items-center gap-4 font-mono text-xs text-primary/40">
        <p>&copy; {new Date().getFullYear()} Paracosm Lab. All rights reserved.</p>
        <div className="flex gap-6">
          <a href="/privacy.html" className="hover:text-primary transition-colors">Privacy</a>
          <a href="/terms.html" className="hover:text-primary transition-colors">Terms</a>
        </div>
      </div>
      
      {/* Decorative large text */}
      <div className="absolute bottom-[-10%] left-0 w-full text-[15vw] font-serif italic text-primary/[0.02] pointer-events-none whitespace-nowrap overflow-hidden leading-none">
        Taskrail
      </div>
    </footer>
  );
};

const PageHeader = ({ eyebrow, title, children }) => (
  <header className="bg-dark text-primary px-6 pt-36 pb-20 relative overflow-hidden">
    <div className="absolute inset-0 bg-[linear-gradient(rgba(232,228,221,0.06)_1px,transparent_1px),linear-gradient(90deg,rgba(232,228,221,0.06)_1px,transparent_1px)] [background-size:48px_48px]"></div>
    <div className="relative max-w-7xl mx-auto">
      <p className="font-mono text-accent text-sm font-bold uppercase tracking-widest mb-5">{eyebrow}</p>
      <h1 className="font-sans font-bold text-5xl md:text-7xl max-w-5xl tracking-tight text-balance mb-8">{title}</h1>
      <div className="font-sans text-xl text-primary/65 max-w-3xl leading-relaxed">{children}</div>
    </div>
  </header>
);

const SolutionsPage = () => (
  <>
    <Navbar />
    <PageHeader eyebrow="Solutions" title="Three operating modes for AI-assisted engineering work.">
      <p>
        Taskrail applies one control model across development, testing, and DevOps:
        define the work, execute with control, then verify, recover, or escalate.
      </p>
    </PageHeader>
    <main className="bg-background px-6 py-20">
      <div className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-6">
        {solutionModes.map(({ name, description, cookbooks }) => (
          <section key={name} className="space-y-5">
            <div className="rounded-[2rem] border border-dark/10 bg-white p-7 min-h-[260px] flex flex-col">
              <p className="font-mono text-accent text-xs font-bold uppercase tracking-widest mb-4">Problem area</p>
              <h2 className="font-sans font-bold text-4xl mb-4">{name}</h2>
              <p className="text-dark/65 leading-relaxed">{description}</p>
            </div>

            {cookbooks
              .map((cookbook) => solutions.find((solution) => solution.category === name && solution.title === cookbook))
              .filter(Boolean)
              .map(({ slug, title, pain, stages }) => (
                <a
                  key={slug}
                  href={`/cookbooks/${slug}`}
                  className="block rounded-[2rem] border border-dark/10 bg-white p-7 transition-all duration-300 hover:-translate-y-1 hover:border-accent/50"
                >
                  <p className="font-mono text-xs uppercase tracking-widest text-dark/35 mb-5">{stages}</p>
                  <h3 className="font-sans font-bold text-2xl mb-3">{title}</h3>
                  <p className="text-dark/62 leading-relaxed">{pain}</p>
                </a>
              ))}
          </section>
        ))}
      </div>
    </main>
    <Footer />
  </>
);

const CookbookPage = ({ cookbook }) => {
  const Icon = cookbook.icon;

  return (
    <>
      <Navbar />
      <PageHeader eyebrow={`${cookbook.category} cookbook`} title={cookbook.title}>
        <p>{cookbook.pain}</p>
      </PageHeader>
      <main className="bg-background px-6 py-20">
        <div className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-[1fr_0.8fr] gap-6">
          <section className="rounded-[2rem] border border-dark/10 bg-white p-8 md:p-10">
            <Icon className="text-accent mb-8" size={36} />
            <h2 className="font-sans font-bold text-4xl mb-5">How Taskrail controls it</h2>
            <p className="text-dark/65 text-lg leading-relaxed mb-8">{cookbook.text}</p>
            <div className="rounded-2xl bg-dark text-primary p-6">
              <p className="font-mono text-accent text-xs font-bold uppercase tracking-widest mb-3">Stage model</p>
              <p className="font-mono text-lg uppercase tracking-widest text-primary/75">{cookbook.stages}</p>
            </div>
          </section>

          <aside className="space-y-6">
            <section className="rounded-[2rem] border border-dark/10 bg-white p-8">
              <h2 className="font-sans font-bold text-3xl mb-5">Artifacts produced</h2>
              <ul className="space-y-3">
                {cookbook.artifacts.map((artifact) => (
                  <li key={artifact} className="flex items-center gap-3 text-dark/70">
                    <Check className="text-accent shrink-0" size={18} />
                    {artifact}
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-[2rem] border border-dark/10 bg-white p-8">
              <h2 className="font-sans font-bold text-3xl mb-4">Human gate</h2>
              <p className="text-dark/65 leading-relaxed">
                Risky or incomplete work stops before completion. Reviewers inspect artifacts,
                traces, checks, and the definition of done before accepting the result.
              </p>
            </section>

            <section className="rounded-[2rem] border border-dark/10 bg-white p-8">
              <h2 className="font-sans font-bold text-3xl mb-4">Proof slots</h2>
              <p className="text-dark/65 leading-relaxed">
                Metrics TBD: completion time, retry success rate, blocked-run resolution time,
                and human intervention rate.
              </p>
            </section>
          </aside>
        </div>
      </main>
      <Footer />
    </>
  );
};

function App() {
  const path = window.location.pathname;
  const cookbookMatch = path.match(/^\/cookbooks\/([^/]+)$/);

  if (path === "/solutions") {
    return <SolutionsPage />;
  }

  if (cookbookMatch) {
    const cookbook = solutions.find((solution) => solution.slug === cookbookMatch[1]);
    return cookbook ? <CookbookPage cookbook={cookbook} /> : <SolutionsPage />;
  }

  return (
    <>
      <Navbar />
      <Hero />
      <Features />
      <Solutions />
      <Philosophy />
      <Protocol />
      <Conversion />
      <Footer />
    </>
  );
}

export default App;
