from setuptools import find_packages, setup

setup(
    name="mbx-gateway",
    version="1.0.0",
    description="MBX - private streaming gateway: search, stream, download",
    packages=find_packages(include=["moviebox_wrapper", "moviebox_wrapper.*"]),
    include_package_data=True,
    package_data={"moviebox_wrapper": ["protocol_default.yaml", "config_default.yaml"]},
    entry_points={
        "console_scripts": [
            "mbx = moviebox_wrapper.cli:main",
        ]
    },
)
