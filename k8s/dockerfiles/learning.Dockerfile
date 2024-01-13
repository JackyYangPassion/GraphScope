# Learning engine

ARG REGISTRY=registry.cn-hongkong.aliyuncs.com
ARG BUILDER_VERSION=latest
ARG RUNTIME_VERSION=latest
FROM $REGISTRY/graphscope/graphscope-dev:$BUILDER_VERSION AS builder

ARG CI=false

COPY --chown=graphscope:graphscope . /home/graphscope/GraphScope

# 创建pip配置文件，使用清华大学的镜像源
RUN mkdir -p /home/graphscope/.pip && \
    echo "[global]\n\
index-url = https://pypi.tuna.tsinghua.edu.cn/simple\n\
[install]\n\
trusted-host = pypi.tuna.tsinghua.edu.cn" > /home/graphscope/.pip/pip.conf

RUN cd /home/graphscope/GraphScope/ && \
    if [ "${CI}" = "true" ]; then \
        cp -r artifacts/learning /home/graphscope/install; \
    else \
        . /home/graphscope/.graphscope_env; \
        mkdir /home/graphscope/install; \
        make learning-install INSTALL_PREFIX=/home/graphscope/install; \
        cd python; \
        python3 -m pip install --user -r requirements.txt; \
        python3 setup.py bdist_wheel; \
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/graphscope/GraphScope/learning_engine/graph-learn/graphlearn/built/lib; \
        auditwheel repair dist/*.whl; \
        python3 -m pip install wheelhouse/*.whl; \
        cp wheelhouse/*.whl /home/graphscope/install/; \
        cd ../coordinator; \
        python3 setup.py bdist_wheel; \
        cp dist/*.whl /home/graphscope/install/; \
    fi

############### RUNTIME: GLE #######################
FROM $REGISTRY/graphscope/vineyard-runtime:$RUNTIME_VERSION AS learning

RUN sudo apt-get update -y && \
    sudo apt-get install -y python3-pip && \
    sudo apt-get clean -y && \
    sudo rm -rf /var/lib/apt/lists/*

RUN sudo chmod a+wrx /tmp

# 复制构建阶段创建的pip配置文件到用户目录
COPY --from=builder /home/graphscope/.pip/pip.conf /home/graphscope/.pip/pip.conf

#to make sure neo4j==5.10.0 can be installed
RUN pip3 install pip==20.3.4 

COPY --from=builder /home/graphscope/install /opt/graphscope/
RUN python3 -m pip install --no-cache-dir /opt/graphscope/*.whl && sudo rm -rf /opt/graphscope/*.whl

ENV PATH=${PATH}:/home/graphscope/.local/bin
