clc
clearvars
%%

animals = {'H1019','H1020','H1021','H1022','H1023','H1024','H1025','H1026'}';
responses = {
    'yes','yes','yes','no','yes';
    'yes','yes','yes','no','yes';
    'yes','yes','yes','no','yes';
    'yes','yes','yes','no','yes';
    'yes','yes','yes','no','yes';
    'yes','yes','yes','no','yes';
    'yes','yes','yes','no','yes';
    'yes','yes','yes','no','yes';
};

conditions = {'50 mA','40 mA','30 mA','20 mA','Stairstep'};

respMat = strcmp(responses, 'yes');

nAnimals = size(respMat,1);
propYes = sum(respMat,1) / nAnimals;   
countYes = sum(respMat,1);             

figure;
bar(propYes, 'FaceColor',[229 115 115]/255, 'EdgeColor','none');
set(gca, 'XTickLabel', conditions, 'XTick', 1:numel(conditions));
ylim([0 1.5]);
ylabel('Proportion of responders');
xlabel('Stimulus condition');
title('Response probability across stimulation conditions');
set(gca, 'FontSize',12,'Box','off');

text(1:numel(propYes), propYes + 0.03, ...
     string(countYes) + "/" + string(nAnimals), ...
     'HorizontalAlignment','center', 'FontSize',10);
