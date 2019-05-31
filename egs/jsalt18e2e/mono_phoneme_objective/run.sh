#!/bin/bash

# Copyright 2017 Johns Hopkins University (Shinji Watanabe)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

# This is a baseline for "JSALT'18 Multilingual End-to-end ASR for Incomplete Data"
# We use 5 Babel language (Assamese Tagalog Swahili Lao Zulu), Librispeech (English), and CSJ (Japanese)
# as a target language, and use 10 Babel language (Cantonese Bengali Pashto Turkish Vietnamese
# Haitian Tamil Kurmanji Tok-Pisin Georgian) as a non-target language.
# The recipe first build language-independent ASR by using non-target languages

. ./path.sh
. ./cmd.sh
. ./conf/lang.conf

# general configuration
backend=pytorch
stage=-1       # start from -1 if you need to start from data download
gpu=            # will be deprecated, please use ngpu
ngpu=0          # number of gpus ("0" uses cpu, otherwise use gpu)
debugmode=1
dumpdir=dump   # directory to dump full features
N=0            # number of minibatches to be used (mainly for debugging). "0" uses all minibatches.
verbose=0      # verbose option
resume=        # Resume the training from snapshot

# feature configuration
do_delta=false # true when using CNN

# network archtecture
# encoder related
etype=blstmp     # encoder architecture type
elayers=4
eunits=320
eprojs=320
subsample=1_2_2_1_1 # skip every n frame from input to nth layers
# decoder related
dlayers=1
dunits=300
# attention related
atype=location
aconv_chans=10
aconv_filts=100

# hybrid CTC/attention
mtlalpha=0.5
phoneme_objective_weight=0.0
phoneme_objective_layer=""

predict_lang=""
predict_lang_alpha=0.1

# minibatch related
batchsize=50
maxlen_in=800  # if input length  > maxlen_in, batchsize is automatically reduced
maxlen_out=150 # if output length > maxlen_out, batchsize is automatically reduced

# optimization related
opt=adadelta
epochs=20

# decoding parameter
beam_size=20
penalty=0.0
maxlenratio=0.0
minlenratio=0.0
ctc_weight=0.3
recog_model=acc.best # set a model to be used for decoding: 'acc.best' or 'loss.best'
lang_grapheme_constraint="" # The name of the language which grapheme set will serve as a constraint for character decoding

# exp tag
tag="" # tag for managing experiments.

train_lang=georgian

. utils/parse_options.sh || exit 1;

# data set
train_set=tr_babel_${train_lang}-mono
train_dev=dt_babel_${train_lang}-mono
recog_set="et_babel_${train_lang}"

echo $train_set
echo $train_dev

# data directories
csjdir=../../csj
libridir=../../librispeech
babeldir=../../babel

. ./path.sh
. ./cmd.sh

# check gpu option usage
if [ ! -z $gpu ]; then
    echo "WARNING: --gpu option will be deprecated."
    echo "WARNING: please use --ngpu option."
    if [ $gpu -eq -1 ]; then
        ngpu=0
    else
        ngpu=1
    fi
fi

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

if [ ${stage} -le 0 ]; then
    # TODO
    # add a check whether the following data preparation is completed or not

    # CSJ Japanese
    if [ ! -d "$csjdir/asr1/data" ]; then
    echo "run $csjdir/asr1/run.sh first"
    exit 1
    fi
    lang_code=csj_japanese
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../csj/asr1/data/train_nodup data/tr_${lang_code}
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../csj/asr1/data/train_dev   data/dt_${lang_code}
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../csj/asr1/data/eval1       data/et_${lang_code}_1
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../csj/asr1/data/eval2       data/et_${lang_code}_2
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../csj/asr1/data/eval3       data/et_${lang_code}_3
    # 1) change wide to narrow chars
    # 2) lower to upper chars
    for x in data/*${lang_code}*; do
        utils/copy_data_dir.sh ${x} ${x}_org
        cat ${x}_org/text | nkf -Z |\
            awk '{for(i=2;i<=NF;++i){$i = toupper($i)} print}' > ${x}/text
        rm -fr ${x}_org
    done

    # librispeech
    lang_code=libri_english
    if [ ! -d "$libridir/asr1/data" ]; then
        echo "run $libridir/asr1/run.sh first"
        exit 1
    fi
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../librispeech/asr1/data/train_960  data/tr_${lang_code}
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../librispeech/asr1/data/dev_clean  data/dt_${lang_code}_clean
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../librispeech/asr1/data/dev_other  data/dt_${lang_code}_other
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../librispeech/asr1/data/test_clean data/et_${lang_code}_clean
    utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../librispeech/asr1/data/test_other data/et_${lang_code}_other

    # Babel
    for x in 101-cantonese 102-assamese 103-bengali 104-pashto 105-turkish 106-tagalog 107-vietnamese 201-haitian 202-swahili 203-lao 204-tamil 205-kurmanji 206-zulu 207-tokpisin 404-georgian; do
        langid=`echo $x | cut -f 1 -d"-"`
        lang_code=`echo $x | cut -f 2 -d"-"`
        if [ ! -d "$babeldir/asr1_${lang_code}/data" ]; then
            echo "run $babeldir/asr1/local/run_all.sh first"
            exit 1
        fi
        utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../babel/asr1_${lang_code}/data/train          data/tr_babel_${lang_code}
        utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../babel/asr1_${lang_code}/data/dev            data/dt_babel_${lang_code}
        utils/copy_data_dir.sh --utt-suffix -${lang_code} ../../babel/asr1_${lang_code}/data/eval_${langid} data/et_babel_${lang_code}
    done

fi

feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
feat_dt_dir=${dumpdir}/${train_dev}/delta${do_delta}; mkdir -p ${feat_dt_dir}
if [ ${stage} -le 1 ]; then

    utils/combine_data.sh data/${train_set}_org data/tr_babel_${train_lang}
    utils/combine_data.sh data/${train_dev}_org data/tr_babel_${train_lang}

    # Append langnames for entries in phoneme_ali file. Eg convert 101_10160_A_20111017_201159_003840 to 101_10160_A_20111017_201159_003840-cantonese
    langname_phoneme_ali="langname_phoneme_ali.txt"
    python3 ./append_langname_to_id.py ${phoneme_ali} > ${langname_phoneme_ali}

    # remove utt having more than 3000 frames or less than 10 frames or
    # remove utt having more than 400 characters or no more than 0 characters
    remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/${train_set}_org data/${train_set}
    remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/${train_dev}_org data/${train_dev}

    # Filter out utterances based on phoneme transcriptions and refine phoneme
    # transcriptions
    for x in ${train_set} ${train_dev} ${recog_set}; do
        echo "Creating txt.phn utterances for ${x}"
        awk '(NR==FNR) {a[$1]=$0; next} ($1 in a){print $0}' data/${x}/text ${langname_phoneme_ali} > data/${x}/text.phn
        # Remove stress symbols
        sed -i -r 's/_["%]//g' data/${x}/text.phn
        ## Remove tonal markers
        sed -i -r 's/_T[A-Z]+//g' data/${x}/text.phn
        ./utils/filter_scp.pl data/${x}/text.phn data/${x}/text > data/${x}/text.tmp
        mv data/${x}/text.tmp data/${x}/text 
        ./utils/fix_data_dir.sh data/${x}
    done

    # compute global CMVN
    compute-cmvn-stats scp:data/${train_set}/feats.scp data/${train_set}/cmvn.ark

    # dump features for training
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${feat_tr_dir}/storage ]; then
    utils/create_split_dir.pl \
        /export/b{13,14,15,16}/${USER}/espnet-data/egs/jsalt18e2e/asr1/dump/${train_set}/delta${do_delta}/storage \
        ${feat_tr_dir}/storage
    fi
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${feat_dt_dir}/storage ]; then
    utils/create_split_dir.pl \
        /export/b{13,14,15,16}/${USER}/espnet-data/egs/jsalt18e2e/asr1/dump/${train_dev}/delta${do_delta}/storage \
        ${feat_dt_dir}/storage
    fi
    dump.sh --cmd "$train_cmd" --nj 40 --do_delta $do_delta \
        data/${train_set}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/train ${feat_tr_dir}
    dump.sh --cmd "$train_cmd" --nj 40 --do_delta $do_delta \
        data/${train_dev}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/dev ${feat_dt_dir}
   for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}; mkdir -p ${feat_recog_dir}
        dump.sh --cmd "$train_cmd" --nj 40 --do_delta $do_delta \
            data/${rtask}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/recog/${rtask} \
            ${feat_recog_dir}
    done
fi

dict=data/lang_1char/train_units.txt
nlsyms=data/lang_1char/non_lang_syms.txt

echo "dictionary: ${dict}"
if [ ${stage} -le 2 ]; then
    ### Task dependent. You have to check non-linguistic symbols used in the corpus.
   echo "stage 2: Dictionary and Json Data Preparation"
    mkdir -p data/lang_1char/

    echo "make a non-linguistic symbol list for all languages"
    cut -f 2- data/tr_*/text | grep -o -P '\[.*?\]|\<.*?\>' | sort | uniq > ${nlsyms}
    cat ${nlsyms}

    echo "<unk> 1" > ${dict} # <unk> must be 1, 0 will be used for "blank" in CTC
    cat data/tr_*/text | text2token.py -s 1 -n 1 -l ${nlsyms} | cut -f 2- -d" " | tr " " "\n" \
    | sort | uniq | grep -v -e '^\s*$' | awk '{print $0 " " NR+1}' >> ${dict}
    wc -l ${dict}

    # make json labels
    data2json.sh --feat ${feat_tr_dir}/feats.scp --nlsyms ${nlsyms} \
         data/${train_set} ${dict} > ${feat_tr_dir}/data.json
    data2json.sh --feat ${feat_dt_dir}/feats.scp --nlsyms ${nlsyms} \
         data/${train_dev} ${dict} > ${feat_dt_dir}/data.json
    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        data2json.sh --feat ${feat_recog_dir}/feats.scp \
            --nlsyms ${nlsyms} data/${rtask} ${dict} > ${feat_recog_dir}/data.json
    done

    #### Phoneme Objective ####

    # Create phoneme dictionary
    echo "<unk> 1" > ${dict}.phn
    cut -d' ' -f2- data/${train_set}/text.phn | tr " " "\n" | sort -u |\
    grep -v '^\s*$' | awk '{print $0 " " NR+1}' >> ${dict}.phn

    # Stash current graphame data.json files.
    mv ${feat_tr_dir}/data.json ${feat_tr_dir}/data.gph.json
    mv ${feat_dt_dir}/data.json ${feat_dt_dir}/data.gph.json
    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        mv ${feat_recog_dir}/data.json ${feat_recog_dir}/data.gph.json
    done

    # Filters out phoneme utterances that don't have a corresponding grapheme
    # transcription
    ./utils/filter_scp.pl data/${train_set}/text \
        data/${train_set}/text.phn > data/${train_set}/text.phn.filt
    mv data/${train_set}/text.phn.filt data/${train_set}/text.phn

    data2json.sh --feat ${feat_tr_dir}/feats.scp \
                 --nlsyms ${nlsyms} \
                 --phn-text data/${train_set}/text.phn \
                 data/${train_set} ${dict}.phn \
                 > ${feat_tr_dir}/data.phn.json

    combine_multimodal_json.py ${feat_tr_dir}/data.json \
                               ${feat_tr_dir}/data.{phn,gph}.json

    ./utils/filter_scp.pl data/${train_dev}/text \
        data/${train_dev}/text.phn > data/${train_dev}/text.phn.filt
    mv data/${train_dev}/text.phn.filt data/${train_dev}/text.phn

    data2json.sh --feat ${feat_dt_dir}/feats.scp \
                 --nlsyms ${nlsyms} \
                 --phn-text data/${train_dev}/text.phn \
                 data/${train_dev} ${dict}.phn \
                 > ${feat_dt_dir}/data.phn.json

    combine_multimodal_json.py ${feat_dt_dir}/data.json \
                               ${feat_dt_dir}/data.{phn,gph}.json

    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        ./utils/filter_scp.pl data/${rtask}/text \
            data/${rtask}/text.phn > data/${rtask}/text.phn.filt
        mv data/${rtask}/text.phn.filt data/${rtask}/text.phn

        data2json.sh --feat ${feat_recog_dir}/feats.scp \
                     --nlsyms ${nlsyms} \
                     --phn-text data/${rtask}/text.phn \
                     data/${rtask} ${dict}.phn \
                     > ${feat_recog_dir}/data.phn.json

        combine_multimodal_json.py ${feat_recog_dir}/data.json \
                                   ${feat_recog_dir}/data.{phn,gph}.json
    done

fi

if [ -z ${tag} ]; then
    expdir=exp/${train_set}_${etype}_e${elayers}_subsample${subsample}_unit${eunits}_proj${eprojs}_d${dlayers}_unit${dunits}_${atype}_aconvc${aconv_chans}_aconvf${aconv_filts}_mtlalpha${mtlalpha}_phonemeweight${phoneme_objective_weight}_${opt}_bs${batchsize}_mli${maxlen_in}_mlo${maxlen_out}
    if ${do_delta}; then
        expdir=${expdir}_delta
    fi
    if [ ${phoneme_objective_layer} ]; then
        expdir=${expdir}_phonemelayer${phoneme_objective_layer}
    fi
    if [[ ${predict_lang} = normal ]]; then
        expdir=${expdir}_predictlang-${predict_lang_alpha}
    fi
    if [[ ${predict_lang} = adv ]]; then
        expdir=${expdir}_predictlang-adv-${predict_lang_alpha}
    fi
else
    expdir=exp/${train_set}_${tag}
fi
mkdir -p ${expdir}

if [ ${stage} -le 3 ]; then
    echo "stage 3: Network Training"
    train_cmd="${cuda_cmd} --gpu ${ngpu} ${expdir}/train.log \
        asr_train.py \
        --ngpu ${ngpu} \
        --backend ${backend} \
        --outdir ${expdir}/results \
        --debugmode ${debugmode} \
        --dict ${dict} \
        --debugdir ${expdir} \
        --minibatches ${N} \
        --verbose ${verbose} \
        --resume ${resume} \
        --train-json ${feat_tr_dir}/data.json \
        --valid-json ${feat_dt_dir}/data.json \
        --etype ${etype} \
        --elayers ${elayers} \
        --eunits ${eunits} \
        --eprojs ${eprojs} \
        --subsample ${subsample} \
        --dlayers ${dlayers} \
        --dunits ${dunits} \
        --atype ${atype} \
        --aconv-chans ${aconv_chans} \
        --aconv-filts ${aconv_filts} \
        --mtlalpha ${mtlalpha} \
        --batch-size ${batchsize} \
        --maxlen-in ${maxlen_in} \
        --maxlen-out ${maxlen_out} \
        --opt ${opt} \
        --epochs ${epochs} \
        --phoneme_objective_weight ${phoneme_objective_weight}"
    if [[ ${phoneme_objective_layer} ]]; then
        train_cmd="${train_cmd} --phoneme_objective_layer ${phoneme_objective_layer}"
    fi
    if [[ ! -z ${predict_lang} ]]; then
        train_cmd="${train_cmd} --predict_lang ${predict_lang}\
                                --predict_lang_alpha ${predict_lang_alpha}"
    fi
    echo "train_cmd: $train_cmd"
    echo "expdir: $expdir"
    ${train_cmd}
fi

if [ ${stage} -le 4 ]; then
    echo "stage 4: Decoding"
    nj=32

    for rtask in ${recog_set}; do
    (
        decode_dir=decode_${rtask}_beam${beam_size}_e${recog_model}_p${penalty}_len${minlenratio}-${maxlenratio}_ctcw${ctc_weight}
        # If lang_grpahame_constraint is specified, pull out the relevant
        # grapheme dictionary from rtask name, where rtask is something like
        # "et_babel_assamese"
        lang_dict="false"
        if [ ${lang_grapheme_constraint} ]; then
            decode_dir=${decode_dir}_graphemeconstraint
            rtask_lang=$(echo $rtask | cut -d "_" -f 3)
            lang_dict=dicts/${rtask_lang}_dict.txt
        fi
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}

        # split data
        splitjson.py --parts ${nj} ${feat_recog_dir}/data.json

        #### use CPU for decoding
        ngpu=0

        ${decode_cmd} JOB=1:${nj} ${expdir}/${decode_dir}/log/decode.JOB.log \
            asr_recog.py \
            --ngpu ${ngpu} \
            --backend ${backend} \
            --recog-json ${feat_recog_dir}/split${nj}utt/data.JOB.json \
            --result-label ${expdir}/${decode_dir}/data.JOB.json \
            --model ${expdir}/results/model.${recog_model}  \
            --model-conf ${expdir}/results/model.conf  \
            --beam-size ${beam_size} \
            --penalty ${penalty} \
            --maxlenratio ${maxlenratio} \
            --minlenratio ${minlenratio} \
            --ctc-weight ${ctc_weight} \
            --phoneme-dict ${dict}.phn \
            --lang-grapheme-constraint ${lang_dict} \
            --train-json ${feat_tr_dir}/data.json \
            &
        wait

        score_sclite.sh --nlsyms ${nlsyms} --wer true ${expdir}/${decode_dir} ${dict} grapheme
        score_sclite.sh --nlsyms ${nlsyms} --wer false ${expdir}/${decode_dir} ${dict}.phn phn

    ) &
    done
    wait
    echo "Finished"
fi
