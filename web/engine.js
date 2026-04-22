// zreal Space Shooter — WebGL2 + WASM SIMD

const ZReal = {
  wasm: null, gl: null, canvas: null,
  prog: null, partProg: null,
  cubeVAO: null, cubeN: 0, sphereVAO: null, sphereN: 0, billVAO: null,

  async init(id) {
    this.canvas = document.getElementById(id);
    this.gl = this.canvas.getContext("webgl2", { antialias: true, alpha: false });
    if (!this.gl) { alert("WebGL2 required"); return; }
    const { instance } = await WebAssembly.instantiate(
      await (await fetch("zreal.wasm")).arrayBuffer(), { env: {} });
    this.wasm = instance;
    this.wasm.exports.init();
    this.buildShaders();
    this.buildGeo();
    this.setupInput();
    this.resize();
    let last = performance.now();
    const loop = (now) => {
      const dt = Math.min((now - last) / 1000, 0.04); last = now;
      this.resize(); this.wasm.exports.frame(dt);
      this.render(); this.updateHUD();
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  },

  resize() {
    const dpr = Math.min(devicePixelRatio||1,2), w=this.canvas.clientWidth, h=this.canvas.clientHeight;
    const pw=w*dpr|0, ph=h*dpr|0;
    if(this.canvas.width!==pw||this.canvas.height!==ph){
      this.canvas.width=pw;this.canvas.height=ph;this.gl.viewport(0,0,pw,ph);this.wasm.exports.setAspect(w/h);}
  },

  buildShaders(){
    const gl=this.gl;
    this.prog=this.link(
      `#version 300 es
      layout(location=0)in vec3 P;layout(location=1)in vec3 N;
      uniform mat4 uMVP,uM;out vec3 vN,vW,vL;
      void main(){gl_Position=uMVP*vec4(P,1);vN=mat3(uM)*N;vW=(uM*vec4(P,1)).xyz;vL=P;}`,
      `#version 300 es
      precision highp float;in vec3 vN,vW,vL;
      uniform vec3 uCol,uLight;uniform float uGlow,uTime;uniform int uKind;
      out vec4 FC;
      void main(){
        vec3 n=normalize(vN),V=normalize(-vW),H=normalize(uLight+V);
        float d=max(dot(n,uLight),0.0),s=pow(max(dot(n,H),0.0),48.0);
        float rim=pow(1.0-max(dot(n,V),0.0),3.0);
        vec3 c;
        if(uKind==0){// player
          c=uCol*(0.15+d*0.6)+s*0.8+rim*vec3(0.3,0.5,1)*0.5+uCol*uGlow;
        }else if(uKind==1){// bullet
          c=uCol*(1.0+uGlow*2.0);// bright emission
        }else if(uKind==2){// enemy
          float pulse=sin(uTime*4.0+vW.x*2.0)*0.5+0.5;
          c=uCol*(0.2+d*0.5)+uCol*uGlow*1.5+s*0.4+rim*uCol*0.3;
          c+=uCol*pulse*0.1;
        }else if(uKind==4){// star
          c=uCol*uGlow*3.0;
        }else if(uKind==5){// powerup
          float p=sin(uTime*6.0)*0.5+0.5;
          c=uCol*(0.5+p*0.5+uGlow)+s*0.5+rim*uCol*0.4;
        }else if(uKind==6){// shield
          c=uCol*uGlow*2.0;c.b+=rim*0.5;
        }else{
          c=uCol*(0.1+d*0.4)+s*0.2+rim*0.15;
        }
        c=c/(c+1.0);c=pow(c,vec3(1.0/2.2));
        FC=vec4(c,uKind==6?0.3:1.0);
      }`);

    this.partProg=this.link(
      `#version 300 es
      layout(location=0)in vec3 aP;uniform mat4 uVP;uniform vec3 uPos;uniform float uSz;
      out vec2 vUV;void main(){gl_Position=uVP*vec4(uPos+aP*uSz,1);vUV=aP.xy+.5;}`,
      `#version 300 es
      precision highp float;in vec2 vUV;uniform vec3 uCol;uniform float uA;out vec4 FC;
      void main(){float d=length(vUV-.5)*2.0;float a=smoothstep(1.,.15,d)*uA;
        float core=smoothstep(.4,.0,d)*uA*.6;FC=vec4(uCol*(a+core)*2.5,a);}`);
  },

  link(vs,fs){const gl=this.gl;
    const s=(t,c)=>{const h=gl.createShader(t);gl.shaderSource(h,c);gl.compileShader(h);
      if(!gl.getShaderParameter(h,gl.COMPILE_STATUS))console.error(gl.getShaderInfoLog(h));return h;};
    const p=gl.createProgram();gl.attachShader(p,s(gl.VERTEX_SHADER,vs));gl.attachShader(p,s(gl.FRAGMENT_SHADER,fs));
    gl.linkProgram(p);if(!gl.getProgramParameter(p,gl.LINK_STATUS))console.error(gl.getProgramInfoLog(p));return p;},

  buildGeo(){const gl=this.gl;
    const C=new Float32Array([-.5,-.5,.5,0,0,1,.5,-.5,.5,0,0,1,.5,.5,.5,0,0,1,-.5,.5,.5,0,0,1,
      .5,-.5,-.5,0,0,-1,-.5,-.5,-.5,0,0,-1,-.5,.5,-.5,0,0,-1,.5,.5,-.5,0,0,-1,
      .5,-.5,.5,1,0,0,.5,-.5,-.5,1,0,0,.5,.5,-.5,1,0,0,.5,.5,.5,1,0,0,
      -.5,-.5,-.5,-1,0,0,-.5,-.5,.5,-1,0,0,-.5,.5,.5,-1,0,0,-.5,.5,-.5,-1,0,0,
      -.5,.5,.5,0,1,0,.5,.5,.5,0,1,0,.5,.5,-.5,0,1,0,-.5,.5,-.5,0,1,0,
      -.5,-.5,-.5,0,-1,0,.5,-.5,-.5,0,-1,0,.5,-.5,.5,0,-1,0,-.5,-.5,.5,0,-1,0]);
    const CI=new Uint16Array([0,1,2,0,2,3,4,5,6,4,6,7,8,9,10,8,10,11,12,13,14,12,14,15,16,17,18,16,18,19,20,21,22,20,22,23]);
    this.cubeVAO=this.mkV(C,CI,24);this.cubeN=CI.length;
    const sv=[],si=[],sl=16,st=10;
    for(let i=0;i<=st;i++){const p=Math.PI*i/st,sp=Math.sin(p),cp=Math.cos(p);
      for(let j=0;j<=sl;j++){const t=2*Math.PI*j/sl;const x=sp*Math.cos(t),y=cp,z=sp*Math.sin(t);
        sv.push(x*.5,y*.5,z*.5,x,y,z);}}
    for(let i=0;i<st;i++)for(let j=0;j<sl;j++){const a=i*(sl+1)+j,b=a+sl+1;si.push(a,b,a+1,b,b+1,a+1);}
    this.sphereVAO=this.mkV(new Float32Array(sv),new Uint16Array(si),24);this.sphereN=si.length;
    const B=new Float32Array([-.5,-.5,0,.5,-.5,0,.5,.5,0,-.5,.5,0]);
    const BI=new Uint16Array([0,1,2,0,2,3]);
    this.billVAO=gl.createVertexArray();gl.bindVertexArray(this.billVAO);
    const bv=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,bv);gl.bufferData(gl.ARRAY_BUFFER,B,gl.STATIC_DRAW);
    const be=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,be);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,BI,gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,3,gl.FLOAT,false,0,0);gl.bindVertexArray(null);
  },

  mkV(v,i,st){const gl=this.gl,a=gl.createVertexArray();gl.bindVertexArray(a);
    const vb=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,vb);gl.bufferData(gl.ARRAY_BUFFER,v,gl.STATIC_DRAW);
    const eb=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,eb);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,i,gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,3,gl.FLOAT,false,st,0);
    gl.enableVertexAttribArray(1);gl.vertexAttribPointer(1,3,gl.FLOAT,false,st,12);
    gl.bindVertexArray(null);return a;},

  setupInput(){
    const c=this.canvas;
    // Mouse: position maps to game field
    c.addEventListener("mousemove",(e)=>{
      const r=c.getBoundingClientRect();
      const x=((e.clientX-r.left)/r.width)*2-1;
      const y=-(((e.clientY-r.top)/r.height)*2-1);
      this.wasm.exports.setInput(x,y);
    });
    // Touch
    c.addEventListener("touchmove",(e)=>{e.preventDefault();
      const t=e.touches[0],r=c.getBoundingClientRect();
      this.wasm.exports.setInput(((t.clientX-r.left)/r.width)*2-1,
        -(((t.clientY-r.top)/r.height)*2-1));},{passive:false});
    c.addEventListener("touchstart",(e)=>{e.preventDefault();
      const t=e.touches[0],r=c.getBoundingClientRect();
      this.wasm.exports.setInput(((t.clientX-r.left)/r.width)*2-1,
        -(((t.clientY-r.top)/r.height)*2-1));},{passive:false});
    // R to restart
    window.addEventListener("keydown",(e)=>{if(e.key==="r"||e.key==="R")this.wasm.exports.restart();});
  },

  render(){
    const gl=this.gl,W=this.wasm.exports,mem=W.memory;
    gl.clearColor(0.01,0.01,0.03,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
    gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.disable(gl.CULL_FACE);

    // Scene objects
    gl.useProgram(this.prog);
    const L=[0.2,0.8,0.4],ll=Math.hypot(...L);
    gl.uniform3f(gl.getUniformLocation(this.prog,"uLight"),L[0]/ll,L[1]/ll,L[2]/ll);
    gl.uniform1f(gl.getUniformLocation(this.prog,"uTime"),W.getTime());

    const cnt=W.getRenderCount(),mvpB=W.getMvpPtr(),modB=W.getModelPtr();

    // First pass: opaque objects
    for(let i=0;i<cnt;i++){
      const k=W.getRenderKind(i);
      if(k===6)continue; // shield is transparent, draw later
      const mvp=new Float32Array(mem.buffer,mvpB+i*64,16);
      const mod=new Float32Array(mem.buffer,modB+i*64,16);
      gl.uniformMatrix4fv(gl.getUniformLocation(this.prog,"uMVP"),false,mvp);
      gl.uniformMatrix4fv(gl.getUniformLocation(this.prog,"uM"),false,mod);
      gl.uniform3f(gl.getUniformLocation(this.prog,"uCol"),W.getRenderColor(i,0),W.getRenderColor(i,1),W.getRenderColor(i,2));
      gl.uniform1f(gl.getUniformLocation(this.prog,"uGlow"),W.getRenderGlow(i));
      gl.uniform1i(gl.getUniformLocation(this.prog,"uKind"),k);
      if(k===4){gl.bindVertexArray(this.cubeVAO);gl.drawElements(gl.TRIANGLES,this.cubeN,gl.UNSIGNED_SHORT,0);}// stars as tiny cubes
      else if(k===1){gl.bindVertexArray(this.cubeVAO);gl.drawElements(gl.TRIANGLES,this.cubeN,gl.UNSIGNED_SHORT,0);}// bullets
      else{gl.bindVertexArray(this.sphereVAO);gl.drawElements(gl.TRIANGLES,this.sphereN,gl.UNSIGNED_SHORT,0);}
    }

    // Transparent pass: shield
    gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE);gl.depthMask(false);
    for(let i=0;i<cnt;i++){
      if(W.getRenderKind(i)!==6)continue;
      const mvp=new Float32Array(mem.buffer,mvpB+i*64,16);
      const mod=new Float32Array(mem.buffer,modB+i*64,16);
      gl.uniformMatrix4fv(gl.getUniformLocation(this.prog,"uMVP"),false,mvp);
      gl.uniformMatrix4fv(gl.getUniformLocation(this.prog,"uM"),false,mod);
      gl.uniform3f(gl.getUniformLocation(this.prog,"uCol"),W.getRenderColor(i,0),W.getRenderColor(i,1),W.getRenderColor(i,2));
      gl.uniform1f(gl.getUniformLocation(this.prog,"uGlow"),W.getRenderGlow(i));
      gl.uniform1i(gl.getUniformLocation(this.prog,"uKind"),6);
      gl.bindVertexArray(this.sphereVAO);gl.drawElements(gl.TRIANGLES,this.sphereN,gl.UNSIGNED_SHORT,0);
    }

    // Particles
    const pC=W.getParticleCount();
    if(pC>0){
      gl.useProgram(this.partProg);
      gl.uniformMatrix4fv(gl.getUniformLocation(this.partProg,"uVP"),false,new Float32Array(mem.buffer,W.getVpPtr(),16));
      gl.bindVertexArray(this.billVAO);
      const pD=new Float32Array(mem.buffer,W.getParticleDataPtr(),pC*8);
      for(let i=0;i<pC;i++){const o=i*8;
        gl.uniform3f(gl.getUniformLocation(this.partProg,"uPos"),pD[o],pD[o+1],pD[o+2]);
        gl.uniform3f(gl.getUniformLocation(this.partProg,"uCol"),pD[o+3],pD[o+4],pD[o+5]);
        gl.uniform1f(gl.getUniformLocation(this.partProg,"uSz"),pD[o+6]);
        gl.uniform1f(gl.getUniformLocation(this.partProg,"uA"),pD[o+7]);
        gl.drawElements(gl.TRIANGLES,6,gl.UNSIGNED_SHORT,0);
      }
    }

    gl.depthMask(true);gl.disable(gl.BLEND);gl.bindVertexArray(null);
  },

  updateHUD(){
    const W=this.wasm.exports;
    const s=document.getElementById("score"),c=document.getElementById("combo"),
      w=document.getElementById("wave"),hp=document.getElementById("hp"),
      st=document.getElementById("state");
    if(s)s.textContent=W.getScore().toLocaleString();
    if(c){const v=W.getCombo();c.textContent=v>1?`×${v}`:"";c.style.opacity=v>1?1:0;}
    if(w)w.textContent="WAVE "+W.getWave();
    if(hp){const h=W.getHP();hp.innerHTML="<span style='color:#f44'>♥</span>".repeat(Math.max(0,h));}
    if(st){const v=W.getGameState();st.textContent=v===1?"DESTROYED — R to restart":"";st.style.opacity=v===1?1:0;}
  },
};
