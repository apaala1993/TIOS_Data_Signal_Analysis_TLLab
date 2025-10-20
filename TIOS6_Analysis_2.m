
clc
clearvars

%%

if ~exist('th','var'),       th       = 0.002; end   % stim threshold (V) [unused in this START/STOP parser]
if ~exist('tbefore','var'),  tbefore  = 5;     end   % seconds BEFORE each START to include
if ~exist('tafter','var'),   tafter   = 5;     end   % seconds AFTER each STOP to include

%% 

session_dir = uigetdir(pwd, 'Select a session folder');
assert(~isequal(session_dir,0) && isfolder(session_dir), 'Invalid folder selection.');

D = dir(fullfile(session_dir, '*.mat'));
assert(~isempty(D), 'No .mat files found in %s', session_dir);
L = lower({D.name});  % lowercase names for matching

% ---- RR (Ch1) ----

idx = find(contains(L,'ch1') & contains(L,'rr'));
if isempty(idx), idx = find(contains(L,'rr')); end
assert(~isempty(idx), 'Could not find an RR (Ch1) file in %s', session_dir);
C = D(idx); [~,k]  = max([C.datenum]); rrFile   = fullfile(C(k).folder, C(k).name);

% ---- STIM (Ch2) ----

idx = find(contains(L,'ch2') & contains(L,'stim'));
if isempty(idx), idx = find(contains(L,'stim')); end
assert(~isempty(idx), 'Could not find a STIM (Ch2) file in %s', session_dir);
C = D(idx); [~,k]   = max([C.datenum]); stimFile = fullfile(C(k).folder, C(k).name);

% ---- SG (Ch3) ----

idx = find(contains(L,'ch3') & contains(L,'sg'));
if isempty(idx), idx = find(contains(L,'sg')); end
assert(~isempty(idx), 'Could not find an SG (Ch3) file in %s', session_dir);
C = D(idx); [~,k]  = max([C.datenum]); sgFile    = fullfile(C(k).folder, C(k).name);

fprintf('Using files:\n  RR  : %s\n  STIM: %s\n  SG  : %s\n', rrFile, stimFile, sgFile);

%% 

Sstim = load(stimFile);  stim = Sstim.data;   fs   = Sstim.samplerate(1);
Srr   = load(rrFile);    RR   = Srr.data;     fsRR = Srr.samplerate(1);
Ssg   = load(sgFile);    SG   = Ssg.data;

metaVars = {'com','comtext','datastart','dataend','firstsampleoffset','blocktimes','tickrate','titles','unittext','unittextmap','rangemin','rangemax'};
for S = {Sstim, Srr, Ssg}
    SS = S{1};
    for mv = metaVars
        if isfield(SS, mv{1}) && ~exist(mv{1},'var')
            eval([mv{1} ' = SS.(mv{1});']);
        end
    end
end

needMeta = ~exist('com','var') || ~exist('comtext','var') || ~exist('datastart','var');
if needMeta
    foundMeta = false;
    for i = 1:numel(D)
        wf = whos('-file', fullfile(D(i).folder, D(i).name));
        wnames = string({wf.name});
        if all(ismember({'com','comtext','datastart'}, wnames))
            Smeta = load(fullfile(D(i).folder, D(i).name), 'com','comtext','datastart','dataend','firstsampleoffset','blocktimes','tickrate','titles','unittext','unittextmap','rangemin','rangemax');
            fields = fieldnames(Smeta);
            for f = 1:numel(fields)
                eval([fields{f} ' = Smeta.(fields{f});']);
            end
            foundMeta = true;
            fprintf('Meta/comments loaded from: %s\n', D(i).name);
            break
        end
    end
    assert(foundMeta, 'Could not locate required comment/meta variables (com, comtext, datastart).');
end

%% 

ncoms = size(com,1);
coms  = zeros(ncoms,2);
coms(:,1) = com(:,5); 
for i = 1:ncoms
    blocknum   = com(i,2);
    coms(i,2)  = datastart(blocknum) + com(i,3);  
end

%% 

labels36 = {
'Vital Sign Check'
'TONGUE-BASE-STIM-50-START'
'TONGUE-BASE-STIM-50-STOP'
'TONGUE-BASE-STIM-40-START'
'TONGUE-BASE-STIM-40-STOP'
'TONGUE-BASE-STIM-30-START'
'TONGUE-BASE-STIM-30-STOP'
'contact with tongue'
'TONGUE-BASE-STIM-NO TENSION-50-START'
'TONGUE-BASE-STIM-NO TENSION-50-STOP'
'adding tension'
'TONGUE-BASE-STIM-HIGH TENSION-50-START'
'TONGUE-BASE-STIM-HIGH TENSION-50-STOP'
'TONGUE-BASE-STIM-LOW TENSION-50-START'
'TONGUE-BASE-STIM-LOW TENSION-50-STOP'
'less tension'
'TONGUE-BASE-STIM-LOWER TENSION-50-START'
'TONGUE-BASE-STIM-1g TENSION-50-START'
'TONGUE-BASE-STIM-1g TENSION-50-STOP'
'TONGUE-BASE-STIM-2g TENSION-50-START'
'TONGUE-BASE-STIM-2g TENSION-50-STOP'
'TONGUE-BASE-STIM-3g TENSION-50-START'
'TONGUE-BASE-STIM-3g TENSION-50-STOP'
'TONGUE-BASE-STIM-4g TENSION-50-START'
'TONGUE-BASE-STIM-4g TENSION-50-STOP'
'TONGUE-BASE-STIM-LOW DIST.-40-START'
'TONGUE-BASE-STIM-LOW DIST.-50-START'
'TONGUE-BASE-STIM-LOW DIST.-40-STOP'
'TONGUE-BASE-STIM-LOW DIST.-50-STOP'
'TONGUE-BASE-STIM-MED. DIST.-50-START'
'TONGUE-BASE-STIM-MED. DIST.-50-STOP'
'STIM ANGLE ADJUSTMENT'
'TONGUE-BASE-STIM-HIGH DIST.-50-START'
'TONGUE-BASE-STIM-HIGH DIST.-50-STOP'
'TONGUE-BASE-STIM-3mm DIST.- 2g TENSION-50-START'
'TONGUE-BASE-STIM-3mm DIST.- 2g TENSION-50-STOP'
};

% Normalize all comtext rows for matching (inline; no functions)
ncomtext = size(comtext,1);
normCom  = strings(ncomtext,1);
for i = 1:ncomtext
    s = string(comtext(i,:));
    s = lower(strtrim(s));
    s = regexprep(s, '\s+', ' ');
    s = regexprep(s, '\s*-\s*', '-');
    normCom(i) = s;
end

%% =========================
%  PART 5: Build stimtype (36 x 3) — no local functions
%          col1 = label (as provided)
%          col2 = vector of matching comment-row indices in comtext
%          col3 = struct with extracted segments for START/STOP pairs:
%                 .windows [N x 2] in stim samples (start, stop)
%                 .comment_rows [N x 2] (startRow, stopRow)
%                 .stim, .sg, .rr = 1xN cell arrays (each cell is a 1D vector)
%  =========================
stimtype = cell(36,3);
fcoef = fs / fsRR;                         % STIM->RR sample-rate ratio
preS  = round(tbefore * fs);               % samples before START
postS = round(tafter  * fs);               % samples after STOP

for i = 1:36
    thisLabelRaw = labels36{i};

    % inline normalization for label
    thisLabel = string(thisLabelRaw);
    thisLabel = lower(strtrim(thisLabel));
    thisLabel = regexprep(thisLabel, '\s+', ' ');
    thisLabel = regexprep(thisLabel, '\s*-\s*', '-');

    % col1: original label (unmodified)
    stimtype{i,1} = thisLabelRaw;

    % col2: match rows in comtext
    hits = find(normCom == thisLabel).';
    stimtype{i,2} = hits;

    % col3: default empty struct
    stimtype{i,3} = struct( ...
        'windows',       zeros(0,2), ...
        'comment_rows',  zeros(0,2), ...
        'stim',          {{}}, ...
        'sg',            {{}}, ...
        'rr',            {{}} );

    % For START labels, try to pair with corresponding STOP and slice data
    if endsWith(thisLabel, "-start")
        % Pairing target: replace trailing "-start" with "-stop"
        baseLab  = erase(thisLabel, "-start");
        stopLab  = baseLab + "-stop";

        startRows = hits;
        stopRows  = find(normCom == stopLab).';

        if isempty(startRows) || isempty(stopRows)
            continue
        end

        % Pair each START with the earliest STOP *after* it (greedy, no reuse)
        usedStop = false(1, numel(stopRows));
        for s = 1:numel(startRows)
            sr = startRows(s);
            % find the first stop row with later absolute time
            sr_time  = coms(sr,2);
            laterIdx = find(~usedStop & (coms(stopRows,2) > sr_time), 1, 'first');
            if isempty(laterIdx)
                continue
            end
            tr = stopRows(laterIdx);
            usedStop(laterIdx) = true;

            % window in STIM/SG sample space
            w0 = max(1, coms(sr,2) - preS);
            w1 = min(numel(stim), coms(tr,2) + postS);
            if w1 <= w0, continue, end

            % slice segments
            segStim = stim(w0:w1);
            segSG   = SG(w0:w1);

            % map to RR indices
            rr0 = max(1, ceil(w0 / fcoef));
            rr1 = min(numel(RR), floor(w1 / fcoef));
            if rr1 <= rr0
                segRR = RR(rr0);
            else
                segRR = RR(rr0:rr1);
            end

            % append to struct
            st = stimtype{i,3};
            st.windows       = [st.windows;      w0, w1];
            st.comment_rows  = [st.comment_rows; sr, tr];
            st.stim{end+1}   = segStim(:).';
            st.sg{end+1}     = segSG(:).';
            st.rr{end+1}     = segRR(:).';
            stimtype{i,3}    = st;
        end
    end
end

fprintf('Built stimtype (36 x 3). START rows have segmented data in col3.\n');

%% =========================
%  (Optional) quick summary print
%  =========================
for i = 1:size(stimtype,1)
    lbl = stimtype{i,1};
    nHits = numel(stimtype{i,2});
    nSegs = numel(stimtype{i,3}.stim);
    fprintf('%2d) %-50s  hits=%-2d  segs=%-2d\n', i, lbl, nHits, nSegs);
end

%%
% Plot each stimulus condition (one figure per condition, 3 subplots: STIM, RR, SG)

if ~exist('tbefore','var'), tbefore = 5; end
if ~exist('tafter','var'),  tafter  = 5; end

stimcond = stimtype(:,1);  % labels from your 36x3 stimtype

for cond = 1:numel(stimcond)
    st = stimtype{cond,3};
    if ~isfield(st,'stim') || isempty(st.stim)
        % no START/STOP pairings (nothing to plot for this label)
        continue
    end
    nSeg = numel(st.stim);

    figure('Name', sprintf('%s (n=%d)', stimcond{cond}, nSeg), 'Color', 'w');

    % ---- STIM (Ch2) ----
    sp1 = subplot(3,1,1); hold on
    for j = 1:nSeg
        t = (0:numel(st.stim{j})-1)/fs - tbefore;
        plot(t, st.stim{j});
    end
    ylabel('V'); title('STIM (Ch2)'); box on

    % ---- RR (Ch1) ----
    sp2 = subplot(3,1,2); hold on
    for j = 1:nSeg
        trr = (0:numel(st.rr{j})-1)/fsRR - tbefore;
        plot(trr, st.rr{j});
    end
    ylabel('a.u.'); title('RR (Ch1)'); box on

    % ---- SG (Ch3) ----
    sp3 = subplot(3,1,3); hold on
    for j = 1:nSeg
        tsg = (0:numel(st.sg{j})-1)/fs - tbefore;
        plot(tsg, st.sg{j});
    end
    ylabel('a.u.'); xlabel('Time (s)'); title('SG (Ch3)'); box on

    sgtitle(sprintf('%s (n=%d)', stimcond{cond}, nSeg));
    linkaxes([sp1, sp2, sp3], 'x');
end
















