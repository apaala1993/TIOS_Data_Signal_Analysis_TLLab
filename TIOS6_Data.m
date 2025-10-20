clc; clearvars; close all;

%% ── Select session folder ────────────────────────────────────────────────
session_dir = uigetdir(pwd, 'Select a session folder');
assert(~isequal(session_dir,0) && isfolder(session_dir), 'No folder selected.');

%% ── Locate channel files ────────────────────────────────────────────────
D = dir(fullfile(session_dir, '*.mat'));
assert(~isempty(D), 'No .mat files in %s', session_dir);

names = lower(string({D.name}));
paths = string(fullfile({D.folder}, {D.name}));

isStim = contains(names,'ch2') & contains(names,'stim');
isRR   = contains(names,'ch1') & (contains(names,'rr') | contains(names,'resp'));
isSG   = contains(names,'ch3') & contains(names,'sg');

if ~any(isStim), isStim = contains(names,'stim'); end
if ~any(isRR),   isRR   = contains(names,'rr') | contains(names,'resp'); end
if ~any(isSG),   isSG   = contains(names,'sg'); end

stimFile = ""; rrFile = ""; sgFile = "";
if any(isStim), stimFile = paths(find(isStim,1,'first')); end
if any(isRR),   rrFile   = paths(find(isRR,  1,'first')); end
if any(isSG),   sgFile   = paths(find(isSG,  1,'first')); end

assert(stimFile~="", 'Could not find STIM (Ch2) file in %s', session_dir);
assert(rrFile~="",   'Could not find RR   (Ch1) file in %s', session_dir);
assert(sgFile~="",   'Could not find SG   (Ch3) file in %s', session_dir);

fprintf('Using files:\n  STIM: %s\n  RR  : %s\n  SG  : %s\n', stimFile, rrFile, sgFile);

%% ── Load channels ───────────────────────────────────────────────────────
Sstim = load(stimFile);                       % expects: data, samplerate(1), comtext, com, datastart
stim  = Sstim.data(:);                        % force column
fs    = Sstim.samplerate(1);
comtext   = Sstim.comtext;
com       = Sstim.com;
datastart = Sstim.datastart;

Srr = load(rrFile);
RR  = Srr.data(:);                            % force column
fsRR = Srr.samplerate(1);

Ssg = load(sgFile);
SG  = Ssg.data(:);                            % force column (assume fs same as STIM)

%% ── Parse TONGUE START/STOP events (absolute fs indices) ────────────────
ncom = size(com,1);
absSamp = zeros(ncom,1);
for i = 1:ncom
    absSamp(i) = datastart(com(i,2)) + com(i,3);  % fs samples
end

normtxt = @(s) upper(regexprep(strrep(strtrim(string(s)), char(160), ' '), '\s+', ' '));

startTimes = containers.Map('KeyType','char','ValueType','any');
stopTimes  = containers.Map('KeyType','char','ValueType','any');
order = strings(0,1);

for i = 1:ncom
    txt = normtxt(comtext(com(i,5),:));
    if ~startsWith(txt,'TONGUE'), continue; end
    if endsWith(txt,'-START')
        base = char(regexprep(txt,'-START$',''));
        if ~isKey(startTimes,base), startTimes(base)=[]; order(end+1)=string(base); end
        v = startTimes(base); v(end+1)=absSamp(i); startTimes(base)=v;
    elseif endsWith(txt,'-STOP')
        base = char(regexprep(txt,'-STOP$',''));
        if ~isKey(stopTimes,base), stopTimes(base)=[]; order(end+1)=string(base); end
        v = stopTimes(base); v(end+1)=absSamp(i); stopTimes(base)=v;
    end
end
labels = unique(order(order~=""),'stable');

%% ── Build START→STOP blocks, slice STIM/SG/RR (RR mapped by time) ───────
cuts = struct('label',{}, 'segments',{}, 'stim',{}, 'sg',{}, 'rr',{});
kout = 0;

for li = 1:numel(labels)
    key = char(labels(li));
    if ~isKey(startTimes,key) || ~isKey(stopTimes,key), continue; end
    sT = sort(startTimes(key)); eT = sort(stopTimes(key));
    if isempty(sT) || isempty(eT), continue; end

    segs = []; j=1;
    for i=1:numel(sT)
        while j<=numel(eT) && eT(j)<=sT(i), j=j+1; end
        if j<=numel(eT), segs(end+1,:)=[sT(i) eT(j)]; j=j+1; end %#ok<AGROW>
    end
    if isempty(segs), continue; end

    kout = kout+1;
    cuts(kout).label    = key;
    cuts(kout).segments = segs;
    cuts(kout).stim     = cell(size(segs,1),1);
    cuts(kout).sg       = cell(size(segs,1),1);
    cuts(kout).rr       = cell(size(segs,1),1);

    for r = 1:size(segs,1)
        st = max(1, segs(r,1));
        en = min(numel(stim), segs(r,2));
        cuts(kout).stim{r} = stim(st:en);
        cuts(kout).sg{r}   = SG(st:en);

        % time-based map to RR + clamp
        t_st = (st-1)/fs;  t_en = (en-1)/fs;
        rr_st = max(1, min(numel(RR), floor(t_st*fsRR)+1));
        rr_en = max(1, min(numel(RR), floor(t_en*fsRR)+1));
        if rr_en >= rr_st
            cuts(kout).rr{r} = RR(rr_st:rr_en);
        else
            cuts(kout).rr{r} = RR(rr_st);   % single-sample fallback
        end
    end
end

fprintf('\n===== DEBUG: TONGUE START/STOP in EVENTS =====\n');
fprintf('%-32s | %6s | %5s\n','Label','Segs','Pulses');
fprintf(repmat('-',1,54)); fprintf('\n');

%% ── Pulse detection & pulse-locked metrics ───────────────────────────────
pre_s = 1.0; post_s = 3.0;                        % windows around each pulse
preS = round(pre_s*fs);  postS = round(post_s*fs);
preR = round(pre_s*fsRR); postR = round(post_s*fsRR);

madK = 3.5; minWidth_s = 0.01; minGap_s = 0.15;
minWidthS = ceil(minWidth_s*fs); minGapS = ceil(minGap_s*fs);

seg_rows = []; pulse_rows = [];

for k = 1:numel(cuts)
    label = string(cuts(k).label);
    segs  = cuts(k).segments;

    for r = 1:size(segs,1)
        stAbs = segs(r,1); enAbs = segs(r,2);
        xStim = cuts(k).stim{r}(:);      % force column
        xSG   = cuts(k).sg{r}(:);        % force column
        xRR   = cuts(k).rr{r}(:);        % force column

        % robust threshold (no toolbox)
        m0 = median(xStim);
        mad0 = median(abs(xStim - m0));
        th = m0 + madK*mad0;

        on = (xStim > th);               % logical column
        rise = find(diff([false; on])==1);
        fall = find(diff([on; false])==-1);
        if ~isempty(rise) && ~isempty(fall) && fall(1)<rise(1), fall(1)=[]; end
        if numel(fall)<numel(rise), fall(end+1)=numel(on); end

        keep = false(numel(rise),1); lastKeep=-Inf;
        for i=1:numel(rise)
            w = fall(i)-rise(i)+1;
            if w>=minWidthS && (rise(i)-lastKeep)>=minGapS
                keep(i)=true; lastKeep=rise(i);
            end
        end
        rise = rise(keep);
        nP = numel(rise);

        % pulse windows & deltas
        STIM_wins=[]; SG_wins=[]; RR_wins=[];
        sg_pre=nan(nP,1); sg_peak=nan(nP,1); sg_delta=nan(nP,1);
        rr_pre=nan(nP,1); rr_post=nan(nP,1); rr_delta=nan(nP,1);

        for p=1:nP
            i0_abs = stAbs + rise(p) - 1;

            % STIM/SG windows (fs)
            aS = max(1, i0_abs - preS);
            bS = min(numel(stim), i0_abs + postS);
            wStim = stim(aS:bS);
            wSG   = SG(aS:bS);

            % RR window (time-map + clamp)
            t0 = (i0_abs-1)/fs;
            i0_rr = max(1, min(numel(RR), floor(t0*fsRR)+1));
            aR = max(1, i0_rr - preR);
            bR = min(numel(RR), i0_rr + postR);
            wRR = RR(aR:bR);

            STIM_wins = padcat(STIM_wins, wStim);
            SG_wins   = padcat(SG_wins,   wSG);
            RR_wins   = padcat(RR_wins,   wRR);

            nPreS = min(preS, numel(wSG)-1);
            if nPreS>=5
                sg_pre(p)=mean(wSG(1:nPreS));
                sg_peak(p)=max(wSG(nPreS+1:end));
                sg_delta(p)=sg_peak(p)-sg_pre(p);
            end
            nPreR = min(preR, numel(wRR)-1);
            if nPreR>=5
                rr_pre(p)=mean(wRR(1:nPreR));
                rr_post(p)=mean(wRR(nPreR+1:end));
                rr_delta(p)=rr_post(p)-rr_pre(p);
            end

            pulse_rows = [pulse_rows; {label, r, p, sg_pre(p), sg_peak(p), sg_delta(p), rr_pre(p), rr_post(p), rr_delta(p)}]; %#ok<AGROW>
        end

        seg_rows = [seg_rows; {label, r, nP, nanmean(sg_delta), nanmean(rr_delta)}]; %#ok<AGROW>
        fprintf('%-32s | %6d | %5d\n', char(label), r, nP);

        % Plots: full block
        tS = (0:numel(xStim)-1)/fs; tR = (0:numel(xRR)-1)/fsRR;
        figure('Color','w','Name',sprintf('%s — block %d', char(label), r));
        tl = tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
        title(tl, sprintf('%s — block %d (%d pulse%s)', char(label), r, nP, 's'));
        nexttile; plot(tS,xStim); ylabel('STIM'); grid on; box off;
        nexttile; plot(tR,xRR);   ylabel('RR');   grid on; box off;
        nexttile; plot(tS,xSG);   ylabel('SG');   grid on; box off; xlabel('s');

        % Plots: pulse-locked overlays + averages
        if nP>=1
            t0S = (-preS:postS)/fs; t0R = (-preR:postR)/fsRR;
            figure('Color','w','Name',sprintf('%s — pulse-locked block %d', char(label), r));
            tl2 = tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
            title(tl2, sprintf('%s — block %d pulse-locked (pre=%.1fs, post=%.1fs)', char(label), r, pre_s, post_s));

            nexttile; hold on;
            for p=1:size(STIM_wins,2), plot(t0S, STIM_wins(:,p)); end
            plot(t0S, nanmean(STIM_wins,2), 'k', 'LineWidth',1.5);
            ylabel('STIM'); grid on; box off;

            nexttile; hold on;
            for p=1:size(RR_wins,2), plot(t0R, RR_wins(:,p)); end
            plot(t0R, nanmean(RR_wins,2), 'k', 'LineWidth',1.5);
            ylabel('RR'); grid on; box off;

            nexttile; hold on;
            for p=1:size(SG_wins,2), plot(t0S, SG_wins(:,p)); end
            plot(t0S, nanmean(SG_wins,2), 'k', 'LineWidth',1.5);
            ylabel('SG'); grid on; box off; xlabel('Time from pulse (s)');
        end
    end
end

%% ── Summaries ────────────────────────────────────────────────────────────
if ~isempty(seg_rows)
    SegmentSummary = cell2table(seg_rows, ...
        'VariableNames', {'Label','Block','NumPulses','MeanDelta_SG','MeanDelta_RR'});
    disp(' '); disp('=== Segment-level summary (Δ = post - pre) ==='); disp(SegmentSummary);
else
    warning('No segments found.');
end

if ~isempty(pulse_rows)
    PulseSummary = cell2table(pulse_rows, ...
        'VariableNames', {'Label','Block','Pulse','SG_Pre','SG_Peak','SG_Delta','RR_Pre','RR_Post','RR_Delta'});
    disp(' '); disp('=== Pulse-level summary (first few rows) ===');
    disp(PulseSummary(1:min(12,height(PulseSummary)),:));
end

%% ── Helper: column-concatenate vectors with NaN padding ─────────────────
function M = padcat(M, v)
    v = v(:);
    if isempty(M)
        M = v;
    else
        L = size(M,1);
        if numel(v) > L
            M = [M; nan(numel(v)-L, size(M,2))]; %#ok<AGROW>
            M = [M, v];
        else
            M = [M, [v; nan(L-numel(v),1)]];
        end
    end
end
